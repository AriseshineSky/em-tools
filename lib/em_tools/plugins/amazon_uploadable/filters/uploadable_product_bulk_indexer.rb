# frozen_string_literal: true

require 'json'

module EmTools
  module Plugins
    module AmazonUploadable
      module Filters
        # Buffers ASIN hits coming from {UploadableProductFilter#each_asin_hit}, deduplicates them,
        # and ships them to Elasticsearch in bulk. Side effects are isolated here so the filter class
        # stays a thin orchestrator.
        class UploadableProductBulkIndexer
          attr_reader :stats

          # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
          # -- explicit collaborators keep this trivially testable; initialization just wires them up.
          def initialize(client:, sink_index:, chunk_size:, dry_run:, refresh:, extract_asin:, build_document:)
            @client = client
            @sink_index = sink_index
            @chunk_size = chunk_size
            @dry_run = dry_run
            @refresh = refresh
            @extract_asin = extract_asin
            @build_document = build_document
            @buffer = []
            @seen = {}
            @stats = UploadableProductFilter::IndexStats.new(
              asin_hits_seen: 0,
              asin_ids_indexed: 0,
              bulk_requests: 0,
              bulk_errors: 0
            )
          end
          # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

          def process(hit)
            @stats.asin_hits_seen += 1
            asin = @extract_asin.call(hit)
            return if asin.empty? || @seen[asin]

            @seen[asin] = true
            @buffer << [asin, @build_document.call(asin, hit)]
            flush! if @buffer.size >= @chunk_size
          end

          def finalize!
            flush!
            @client.refresh(@sink_index) if @refresh && !@dry_run
          end

          private

          def flush!
            return if @buffer.empty?

            unless @dry_run
              @stats.bulk_requests += 1
              @stats.bulk_errors += count_bulk_errors(send_bulk(@buffer))
            end
            @stats.asin_ids_indexed += @buffer.size
            @buffer.clear
          end

          def send_bulk(id_body_pairs)
            lines = id_body_pairs.flat_map do |id, body|
              [JSON.generate(index: { _index: @sink_index, _id: id }), JSON.generate(body)]
            end
            @client.bulk(body: "#{lines.join("\n")}\n")
          end

          def count_bulk_errors(resp)
            return 0 unless resp.is_a?(Hash)

            Array(resp['items']).count { |item| item.values.first&.dig('error') }
          end
        end
      end
    end
  end
end
