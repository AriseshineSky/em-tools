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
        #
        # == Optional output shaping (+converter+)
        #
        # After a document passes +policy+, an optional +converter+ may rewrite
        # the payload that is written to NDJSON (price math, field renames,
        # calling an external translator, building rows for
        # +product-validator-ruby+, etc.). Duck type:
        #
        #   converter.call(source_hash)  # => Hash (or any +JSON.generate+-able value),
        #   or +:skip+ to omit the line (filtered count is surfaced in the return hash).
        #
        # Keyword checks still see the **raw** +_source+ from Elasticsearch;
        # the converter runs only for rows that are not blocked.
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
          # @param converter [#call, nil] optional; +.call(es_source)+ returns the
          #   value serialized to each NDJSON line for non-blocked docs, or +:skip+
          #   to drop the row without writing.
          # @param logger [::Logger, nil]
          def initialize(client: nil, query: nil, index: nil, policy: nil,
            blocked_output_path: nil, converter: nil, logger: nil)
            @client = client
            @index = index || EXPORTER_KEY
            resolved_query = query.nil? ? Queries::ProductsQuery.new : query
            @query = resolved_query.to_h
            @policy = policy
            @blocked_output_path = blocked_output_path
            @converter = converter
            @logger = logger
          end

          def to_jsonl(file_path, batch_size: 1000)
            File.open(file_path, "w") do |f|
              write_jsonl(f, batch_size: batch_size)
            end
          end

          def write_jsonl(io, batch_size: 1000)
            total = written = blocked = filtered = 0
            with_blocked_io do |blocked_io|
              each_hit(batch_size: batch_size) do |hit|
                total += 1
                source = hit["_source"]
                if @policy&.blocked?(source)
                  blocked += 1
                  record_blocked!(blocked_io, hit)
                else
                  payload = ndjson_payload(source)
                  if skip_ndjson_line?(payload)
                    filtered += 1
                  else
                    io.puts(JSON.generate(payload))
                    written += 1
                  end
                end
              end
            end
            log_summary!(total: total, written: written, blocked: blocked, filtered: filtered)
            { total: total, written: written, blocked: blocked, filtered: filtered }
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

          def ndjson_payload(source)
            return source unless @converter

            @converter.call(source)
          end

          def skip_ndjson_line?(payload)
            payload == :skip
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

          def log_summary!(total:, written:, blocked:, filtered:)
            return unless @logger

            keyword_count = @policy.respond_to?(:keyword_count) ? @policy.keyword_count : nil
            @logger.info do
              base = "[Oliveyoung] index=#{@index} total=#{total} written=#{written} blocked=#{blocked} filtered=#{filtered}"
              keyword_count ? "#{base} keywords=#{keyword_count}" : base
            end
          end
        end
      end
    end
  end
end
