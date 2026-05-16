# frozen_string_literal: true

require "json"

module EmTools
  module Plugins
    module Lotteon
      module Exporters
        # Streams Lotteon products from Elasticsearch as NDJSON (+user1_lotteon_products+
        # by default, from exporter config). Optional **keyword exclusion policy** and
        # **converter** (+Formatting::ProductExportFormatter+ for upload payloads) match
        # the composition pattern used by {EmTools::Plugins::Oliveyoung::Exporters::ProductsExporter}.
        class ProductsExporter
          EXPORTER_KEY = "lotteon_products"

          def initialize(client: nil, index: nil, policy: nil, blocked_output_path: nil,
            converter: nil, logger: nil)
            @client = client || EmTools::Clients::ElasticsearchClient.new(
              url: EmTools::Core::Config.exporter_elasticsearch_url(EXPORTER_KEY),
            )
            @index = index || EmTools::Core::Config.exporter_index(EXPORTER_KEY, "user1_lotteon_products")
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

          def each(batch_size: 1000, &block)
            each_hit(batch_size: batch_size, &block)
          end

          private

          def each_hit(batch_size:, &block)
            @client.iterate_all(index: @index, batch_size: batch_size, &block)
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
              base = "[Lotteon] index=#{@index} total=#{total} written=#{written} blocked=#{blocked} filtered=#{filtered}"
              keyword_count ? "#{base} keywords=#{keyword_count}" : base
            end
          end
        end
      end
    end
  end
end
