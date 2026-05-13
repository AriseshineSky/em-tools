# frozen_string_literal: true

require "json"

module EmTools
  module Plugins
    module AmazonUploadable
      module Sinks
        # Bulk-indexes formatted uploadable feed rows into Elasticsearch.
        class UploadableFeedEs
          include EmTools::Core::Ports::RecordSink

          def initialize(client:, index:, batch_size: 500, refresh: false)
            @client = client
            @index = index.to_s.strip
            raise ArgumentError, "index is required" if @index.empty?

            @batch_size = [batch_size.to_i, 1].max
            @refresh = refresh ? true : false
            @buffer = []
            @written = 0
            @bulk_requests = 0
            @bulk_errors = 0
          end

          def index(record)
            id = record_id(record)
            @buffer << [id, record]
            @written += 1
            flush! if @buffer.size >= @batch_size
          end

          def close
            flush!
            @client.refresh(@index) if @refresh
          end

          def stats
            {
              es_index: @index,
              es_written: @written,
              es_bulk_requests: @bulk_requests,
              es_bulk_errors: @bulk_errors,
            }
          end

          def describe
            { kind: "elasticsearch", index: @index, batch_size: @batch_size, refresh: @refresh }
          end

          private

          def flush!
            return if @buffer.empty?

            @bulk_requests += 1
            resp = @client.bulk(body: bulk_body(@buffer))
            @bulk_errors += count_bulk_errors(resp)
            @buffer.clear
          end

          def bulk_body(rows)
            chunks = []
            rows.each do |id, body|
              chunks << JSON.generate(index: { _index: @index, _id: id })
              chunks << JSON.generate(body)
            end
            "#{chunks.join("\n")}\n"
          end

          def record_id(record)
            value = record["source_product_id"] || record[:source_product_id] || record["asin"] || record[:asin]
            value.to_s.strip.upcase
          end

          def count_bulk_errors(resp)
            return 0 unless resp.is_a?(Hash)

            items = resp["items"] || []
            items.count { |item| item.values.first&.dig("error") }
          end
        end
      end
    end
  end
end
