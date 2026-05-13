# frozen_string_literal: true

require "json"

module EmTools
  module Plugins
    module Oliveyoung
      module Exporters
        # Streams Oliveyoung products out of Elasticsearch as NDJSON.
        #
        # The shape of "what is an Oliveyoung product" lives in
        # {EmTools::Plugins::Oliveyoung::Queries::ProductsQuery} — this class
        # only owns transport (PIT scan + NDJSON serialisation) and an
        # **optional keyword exclusion policy** that drops docs whose
        # +title+/+brand+ hit a prohibited-keyword list.
        #
        # The policy interface is the same one {EmTools::Core::Sinks::IndexDumper}
        # uses, so any object responding to +#blocked?(source_hash)+ works:
        #
        #   policy.blocked?(source)         # required, Boolean
        #   policy.matched(source)          # optional, Array<String> for the side-file
        #   policy.blocked_record(source,   # optional, Hash to write per-rejection
        #     id: hit_id)
        #   policy.keyword_count            # optional, surfaces in logs
        #
        # Construction: domain rules (filtering) are injected, never built
        # here. The {EmTools::Plugins::Oliveyoung::Plugin#products_exporter}
        # factory is the place that wires +Core::Blacklist::Loader+ +
        # +Strategy::TitleBrand+ into a +policy+ — keep it that way.
        class ProductsExporter
          EXPORTER_KEY = "oliveyoung_products"

          # @param client [EmTools::Clients::ElasticsearchClient, nil] optional;
          #   defaults from {EmTools::Core::Config}.
          # @param query [Hash, #to_h] ES query value (no +query:+ envelope).
          #   Defaults to {Queries::ProductsQuery} with stock settings.
          # @param index [String, nil] override the index name.
          # @param policy [#blocked?, nil] optional keyword exclusion policy.
          #   When supplied, docs for which +policy.blocked?(source)+ returns
          #   true are dropped from NDJSON output.
          # @param blocked_output_path [String, nil] when both +policy+ and
          #   this are set, every dropped doc is appended to this NDJSON file
          #   so callers can audit *which* products were excluded and *why*.
          # @param logger [::Logger, nil]
          def initialize(client: nil, query: nil, index: nil, policy: nil,
            blocked_output_path: nil, logger: nil)
            @client = client || EmTools::Clients::ElasticsearchClient.new(
              url: EmTools::Core::Config.exporter_elasticsearch_url(EXPORTER_KEY),
            )
            @index = index || EmTools::Core::Config.exporter_index(EXPORTER_KEY, "oliveyoung_products")
            @query = (query || Queries::ProductsQuery.new).then { |q| q.respond_to?(:to_h) ? q.to_h : q }
            @policy = policy
            @blocked_output_path = blocked_output_path
            @logger = logger || EmTools::Core::Logger.for(progname: "oliveyoung-export")
          end

          def to_jsonl(file_path, batch_size: 1000)
            File.open(file_path, "w") do |f|
              write_jsonl(f, batch_size: batch_size)
            end
          end

          def write_jsonl(io, batch_size: 1000)
            total = written = blocked = 0
            with_blocked_io do |blocked_io|
              each_hit(batch_size: batch_size) do |hit|
                total += 1
                source = hit["_source"]
                if @policy&.blocked?(source)
                  blocked += 1
                  record_blocked!(blocked_io, hit)
                else
                  io.puts(source.to_json)
                  written += 1
                end
              end
            end
            log_summary!(total: total, written: written, blocked: blocked)
            { total: total, written: written, blocked: blocked }
          end
          # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

          # Convenience for callers that only want the raw stream (no policy
          # check, no NDJSON serialisation). Mirrors the pre-policy API.
          def each(batch_size: 1000, &block)
            each_hit(batch_size: batch_size, &block)
          end

          private

          def each_hit(batch_size:, &block)
            @client.iterate_query(index: @index, query: @query, batch_size: batch_size, &block)
          end

          def with_blocked_io(&block)
            if @blocked_output_path && @policy
              File.open(@blocked_output_path, "w", &block)
            else
              block.call(nil)
            end
          end

          def record_blocked!(blocked_io, hit)
            return unless blocked_io
            return unless @policy.respond_to?(:matched)

            source = hit["_source"] || {}
            record = blocked_record_for(hit, source)
            blocked_io.puts(JSON.generate(record))
          end

          def blocked_record_for(hit, source)
            return @policy.blocked_record(source, id: hit["_id"]) if @policy.respond_to?(:blocked_record)

            {
              "_id" => hit["_id"],
              "title" => source["title"],
              "brand" => source["brand"],
              "matched" => @policy.matched(source),
            }
          end

          def log_summary!(total:, written:, blocked:)
            keyword_count = @policy.respond_to?(:keyword_count) ? @policy.keyword_count : nil
            @logger.info do
              base = "[Oliveyoung] index=#{@index} total=#{total} written=#{written} blocked=#{blocked}"
              keyword_count ? "#{base} keywords=#{keyword_count}" : base
            end
          end
        end
      end
    end
  end
end
