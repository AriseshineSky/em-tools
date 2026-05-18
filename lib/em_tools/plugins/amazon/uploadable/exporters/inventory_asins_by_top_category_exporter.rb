# frozen_string_literal: true

require "set"

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Exporters
          # Scrolls +em_inventory+ for a +source+ (e.g. +amz_de+), collects +source_product_id+,
          # then groups by +top_category+ via {AsinsByTopCategoryExporter}.
          class InventoryAsinsByTopCategoryExporter
            DEFAULT_INVENTORY_INDEX = "em_inventory"
            DEFAULT_SOURCE_FIELD = "source"
            DEFAULT_ID_FIELD = "source_product_id"

            def initialize(es_client:, source:, marketplace:, output_dir:,
              inventory_index: DEFAULT_INVENTORY_INDEX, product_index: nil,
              source_field: DEFAULT_SOURCE_FIELD, id_field: DEFAULT_ID_FIELD,
              category_from: :top_category, logger: nil)
              @es = es_client
              @source = source.to_s.strip
              @marketplace = marketplace.to_s.strip.downcase
              @inventory_index = inventory_index.to_s.strip
              @product_index = product_index.to_s.strip
              @product_index = AsinsByTopCategoryExporter.index_for_marketplace(@marketplace) if @product_index.empty?
              @source_field = source_field.to_s.strip
              @id_field = id_field.to_s.strip
              @output_dir = output_dir
              @category_from = category_from
              @logger = logger || EmTools::Core::Logger.for(progname: "amazon-products")
            end

            # @return [Hash] summary from {AsinsByTopCategoryExporter}
            def export!
              raise ArgumentError, "source is required (e.g. amz_de)" if @source.empty?
              raise ArgumentError, "marketplace is required" if @marketplace.empty?

              unless @es.index_exists?(@inventory_index)
                raise EmTools::Core::Errors::ConfigurationError,
                  "Elasticsearch index not found: #{@inventory_index}"
              end

              label = "#{@inventory_index} source:#{@source}"
              writer = AsinsByTopCategoryExporter.new(
                es_client: @es,
                product_index: @product_index,
                output_dir: @output_dir,
                marketplace: @marketplace,
                category_from: @category_from,
                logger: @logger,
              )

              asin_count = stream_inventory_asins!(writer)
              summary = writer.finalize_export!(label, asin_count).merge(
                inventory_index: @inventory_index,
                inventory_source: @source,
              )
            end

            def self.marketplace_from_source(source)
              mp = source.to_s.strip.sub(/\Aamz_/i, "").downcase
              raise ArgumentError, "cannot infer marketplace from source: #{source.inspect}" if mp.empty?

              mp
            end

            private

            SCROLL_BATCH = 2_000
            MGET_FLUSH = 500

            def stream_inventory_asins!(writer)
              seen = Set.new
              pending = []
              total = 0

              @es.iterate_query(
                index: @inventory_index,
                query: build_query,
                batch_size: SCROLL_BATCH,
              ) do |hit|
                raw = extract_id(hit)
                next if raw.nil?

                id = raw.to_s.strip.upcase
                next if id.empty? || seen.include?(id)

                seen << id
                pending << id
                next if pending.size < MGET_FLUSH

                writer.append_asins!(pending)
                total += pending.size
                pending = []
                @logger.info { "inventory scroll: #{total} distinct ASINs processed" } if (total % 10_000).zero?
              end

              unless pending.empty?
                writer.append_asins!(pending)
                total += pending.size
              end
              total
            end

            def build_query
              field = @source_field
              field = "#{field}.keyword" unless field.include?(".")

              { bool: { filter: [{ terms: { field => source_term_variants(@source) } }] } }
            end

            def source_term_variants(source)
              base = source.to_s.strip
              [base, base.upcase, base.downcase].uniq
            end

            def extract_id(hit)
              src = hit["_source"]
              return unless src.is_a?(Hash)

              src[@id_field] || src[@id_field.to_sym]
            end
          end
        end
      end
    end
  end
end
