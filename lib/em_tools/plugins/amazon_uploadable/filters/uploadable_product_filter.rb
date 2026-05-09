# frozen_string_literal: true

require 'time'

module EmTools
  module Plugins
    module AmazonUploadable
      module Filters
        # Ruby counterpart to +em_tasks.applications.tools.amazon.uploadable_product_filter+ (phase 1).
        #
        # Resolves ASIN stream options like the Python +asin_stream_options+ module, builds an Elasticsearch
        # bool query (time range + optional label term), and streams matching ASINs from +amz_asins_<mp>+
        # using a point-in-time search. Results can either be written line-by-line to an +IO+
        # (see {#stream_asins!}) or bulk-indexed into another ES index (see {#bulk_index_asins!}).
        #
        # The full Python pipeline (offers, price rules, rule engine, metrics index) is not ported yet; use
        # this for ASIN extraction / parity with CLI flags, or extend this class.
        # rubocop:disable Metrics/ClassLength -- cohesive: query builder + sink doc builder + bulk orchestrator.
        class UploadableProductFilter
          IndexStats = Struct.new(
            :asin_hits_seen,
            :asin_ids_indexed,
            :bulk_requests,
            :bulk_errors,
            keyword_init: true
          )

          DEFAULT_BULK_CHUNK_LINES = 500
          DEFAULT_BATCH_SIZE = 500

          attr_reader :marketplace, :asin_index, :ttl, :stream_opts

          # rubocop:disable Metrics/ParameterLists -- one keyword per CLI flag; mirrors the Python entrypoint.
          def initialize(marketplace:, ttl: 30, config: nil,
                         asin_since_days: 7, asin_time_field: nil, asin_cutoff: nil,
                         asin_label: nil, asin_label_field: nil)
            @marketplace = normalize_marketplace(marketplace)
            @asin_index = "amz_asins_#{@marketplace}"
            @ttl = ttl.to_i
            @config = config.is_a?(Hash) ? config : {}
            @stream_opts = resolve_stream_opts(
              asin_since_days, asin_time_field, asin_cutoff, asin_label, asin_label_field
            )
          end
          # rubocop:enable Metrics/ParameterLists

          def resolved_time_field
            Stream::AsinStreamOptions.effective_time_field(@stream_opts[:time_field], @asin_index)
          end

          def cutoff_time_utc
            c = @stream_opts[:cutoff]
            return c if c

            days = [@stream_opts[:relative_days].to_i, 1].max
            Time.now.utc - (days * 86_400)
          end

          def asin_query
            must = [{ range: { resolved_time_field => { gt: cutoff_time_utc.iso8601(3) } } }]
            must << { term: { @stream_opts[:label_field].to_s => @stream_opts[:label] } } if label_filter?
            { bool: { must: must } }
          end

          def stream_asins!(client:, io: $stdout, max_asins: nil)
            each_asin_hit(client: client, max_hits: max_asins) do |hit|
              asin = extract_asin(hit)
              io.puts(asin) unless asin.empty?
            end
          end

          def default_sink_index
            "amz_uploadable_asins_#{@marketplace}"
          end

          # Bulk-index matched ASINs into a destination Elasticsearch index. Each document uses the
          # ASIN as its +_id+ so reruns idempotently overwrite (action: +index+).
          #
          # @return [IndexStats]
          # rubocop:disable Metrics/ParameterLists -- one keyword per CLI flag.
          def bulk_index_asins!(client:, sink_index: nil, max_asins: nil,
                                bulk_chunk_lines: DEFAULT_BULK_CHUNK_LINES,
                                dry_run: false, refresh: false)
            indexer = build_indexer(client, sink_index, bulk_chunk_lines, dry_run, refresh)
            each_asin_hit(client: client, max_hits: max_asins) { |hit| indexer.process(hit) }
            indexer.finalize!
            indexer.stats
          end
          # rubocop:enable Metrics/ParameterLists

          # Yields each hit from the ASIN index stream (same query as +stream_asins!+).
          def each_asin_hit(client:, max_hits: nil, batch_size: DEFAULT_BATCH_SIZE, &block)
            client.iterate_query(
              index: @asin_index,
              query: asin_query,
              batch_size: batch_size,
              max_hits: max_hits,
              &block
            )
          end

          def describe
            {
              marketplace: @marketplace,
              asin_index: @asin_index,
              ttl: @ttl,
              time_field: resolved_time_field,
              cutoff: cutoff_time_utc.iso8601(3),
              label: @stream_opts[:label],
              label_field: @stream_opts[:label_field],
              relative_days: @stream_opts[:relative_days]
            }
          end

          private

          def resolve_stream_opts(since_days, time_field, cutoff, label, label_field)
            Stream::AsinStreamOptions.resolve(
              @config,
              cli_since_days: since_days,
              cli_time_field: time_field,
              cli_cutoff: cutoff,
              cli_label: label,
              cli_label_field: label_field
            )
          end

          def normalize_marketplace(value)
            mp = value.to_s.downcase.strip
            raise ArgumentError, 'marketplace is required' if mp.empty?

            mp
          end

          def normalize_sink_index(sink_index)
            name = sink_index.to_s.strip
            name.empty? ? default_sink_index : name
          end

          def label_filter?
            label = @stream_opts[:label]
            !label.nil? && !label.to_s.strip.empty?
          end

          def extract_asin(hit)
            src = hit['_source'] || {}
            (src['asin'] || hit['_id']).to_s.strip
          end

          def build_indexer(client, sink_index, bulk_chunk_lines, dry_run, refresh)
            UploadableProductBulkIndexer.new(
              client: client,
              sink_index: normalize_sink_index(sink_index),
              chunk_size: [bulk_chunk_lines.to_i, 1].max,
              dry_run: dry_run ? true : false,
              refresh: refresh ? true : false,
              extract_asin: method(:extract_asin),
              build_document: method(:build_sink_document)
            )
          end

          def build_sink_document(asin, hit)
            src = hit['_source'] || {}
            {
              'asin' => asin,
              'marketplace' => @marketplace,
              'source_index' => @asin_index,
              'source_id' => hit['_id'],
              'processed_at' => Time.now.utc.iso8601(3)
            }.merge(time_metadata(src)).merge(label_metadata(src))
          end

          def time_metadata(src)
            metadata_for(src, resolved_time_field, key_field: 'source_time_field', key_value: 'source_time_value')
          end

          def label_metadata(src)
            field = @stream_opts[:label_field].to_s
            return {} if field.empty?

            metadata_for(src, field, key_field: 'label_field', key_value: 'label_value')
          end

          def metadata_for(src, field, key_field:, key_value:)
            value = src[field] || src[field.to_sym]
            meta = { key_field => field }
            meta[key_value] = value if value
            meta
          end
        end
        # rubocop:enable Metrics/ClassLength
      end
    end
  end
end
