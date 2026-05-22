# frozen_string_literal: true

require "fileutils"

module EmTools
  module Plugins
    module Ebay
      module Inventory
        # Reads eBay item ids from a local file, looks up matching rows (+source+ +
        # +source_product_id+), exports +product_id+ (one per line).
        class ProductIdsFromFileExporter
          DEFAULT_INDEX = "user1_ebay_us_products"
          DEFAULT_INVENTORY_INDEX = DEFAULT_INDEX # legacy alias
          DEFAULT_SOURCE = "Ebay_US"
          DEFAULT_SOURCE_FIELD = "source"
          DEFAULT_LOOKUP_FIELD = "source_product_id"
          DEFAULT_OUTPUT_FIELD = "product_id"
          SEARCH_BATCH = 1_000
          SEARCH_SIZE = 10_000

          def initialize(es_client:, source: DEFAULT_SOURCE,
            index: nil, inventory_index: nil,
            source_field: DEFAULT_SOURCE_FIELD,
            lookup_field: DEFAULT_LOOKUP_FIELD,
            output_field: DEFAULT_OUTPUT_FIELD,
            logger: nil)
            @es = es_client
            @source = source.to_s.strip
            resolved = index || inventory_index || DEFAULT_INDEX
            @inventory_index = resolved.to_s.strip
            @source_field = source_field.to_s.strip
            @lookup_field = lookup_field.to_s.strip
            @output_field = output_field.to_s.strip
            @logger = logger || EmTools::Core::Logger.for(progname: "ebay-inventory")
          end

          # @param input_path [String] one eBay item id per line
          # @param output_path [String] one inventory +product_id+ per matched line
          # @return [Hash] summary
          def export!(input_path:, output_path:)
            raise ArgumentError, "source is required" if @source.empty?

            unless @es.index_exists?(@inventory_index)
              raise EmTools::Core::Errors::ConfigurationError,
                "Elasticsearch index not found: #{@inventory_index}"
            end

            lookup_ids = EmTools::Core::Inventory::AsinListReader.read!(input_path)
            product_ids = lookup_inventory_product_ids(lookup_ids)

            path = File.expand_path(output_path)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, "#{product_ids.join("\n")}\n")

            summary = {
              input_path: File.expand_path(input_path),
              inventory_index: @inventory_index,
              source: @source,
              lookup_ids: lookup_ids.size,
              matched_rows: product_ids.size,
              output_path: path,
            }
            @logger.info { summary.map { |k, v| "#{k}=#{v}" }.join(" ") }
            summary
          end

          private

          def lookup_inventory_product_ids(lookup_ids)
            return [] if lookup_ids.empty?

            by_lookup = {}
            lookup_ids.each_slice(SEARCH_BATCH) do |batch|
              fetch_batch(batch).each do |lookup_value, product_id|
                by_lookup[lookup_value] ||= []
                by_lookup[lookup_value] << product_id unless product_id.empty?
              end
            end

            lookup_ids.flat_map { |id| by_lookup[id] || [] }
          end

          def fetch_batch(batch)
            body = {
              size: SEARCH_SIZE,
              _source: [@output_field, @lookup_field],
              query: {
                bool: {
                  filter: [
                    source_filter,
                    { terms: { keyword_field(@lookup_field) => batch } },
                  ],
                },
              },
            }
            resp = @es.search(index: @inventory_index, body: body)
            Array(resp.dig("hits", "hits")).filter_map do |hit|
              src = hit["_source"]
              next unless src.is_a?(Hash)

              lookup = field_value(src, @lookup_field)
              product_id = field_value(src, @output_field)
              next if lookup.empty? || product_id.empty?

              [lookup, product_id]
            end
          end

          def source_filter
            { terms: { keyword_field(@source_field) => source_term_variants(@source) } }
          end

          def source_term_variants(source)
            base = source.to_s.strip
            [base, base.upcase, base.downcase].uniq
          end

          def keyword_field(name)
            name.include?(".") ? name : "#{name}.keyword"
          end

          def field_value(source, name)
            return source[name].to_s.strip if source.key?(name)

            sym = name.to_sym
            return source[sym].to_s.strip if source.key?(sym)

            ""
          end
        end
      end
    end
  end
end
