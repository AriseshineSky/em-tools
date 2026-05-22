# frozen_string_literal: true

require "fileutils"

module EmTools
  module Plugins
    module Ebay
      module Products
        # Streams +product_id+ values from an eBay products index matching an ES query
        # (and optional per-document Ruby filter).
        class ProductIdsExporter
          DEFAULT_INDEX = "user1_ebay_products"
          DEFAULT_ID_FIELD = "product_id"

          def initialize(es_client:, index: DEFAULT_INDEX, id_field: DEFAULT_ID_FIELD,
            query:, source_filter: nil, logger: nil)
            @es = es_client
            @index = index.to_s.strip
            @id_field = id_field.to_s.strip
            @query = query
            @source_filter = source_filter
            @logger = logger || EmTools::Core::Logger.for(progname: "ebay-products")
          end

          # @param output_path [String] one product_id per line
          # @return [Hash] summary
          def export!(output_path)
            raise ArgumentError, "index is required" if @index.empty?
            raise ArgumentError, "id_field is required" if @id_field.empty?
            raise ArgumentError, "query is required" if @query.nil?

            unless @es.index_exists?(@index)
              raise EmTools::Core::Errors::ConfigurationError,
                "Elasticsearch index not found: #{@index}"
            end

            path = File.expand_path(output_path)
            FileUtils.mkdir_p(File.dirname(path))

            ids = []
            @es.iterate_query(index: @index, query: @query, batch_size: 2_000) do |hit|
              next if @source_filter && !@source_filter.call(hit["_source"])

              id = extract_id(hit)
              ids << id unless id.empty?
            end

            File.write(path, "#{ids.join("\n")}\n")

            summary = {
              index: @index,
              output_path: path,
              exported_ids: ids.size,
            }
            @logger.info { summary.map { |k, v| "#{k}=#{v}" }.join(" ") }
            summary
          end

          private

          def extract_id(hit)
            src = hit["_source"]
            if src.is_a?(Hash)
              raw = src[@id_field] || src[@id_field.to_sym]
              return raw.to_s.strip unless raw.to_s.strip.empty?
            end
            hit["_id"].to_s.strip
          end
        end
      end
    end
  end
end
