# frozen_string_literal: true

require "fileutils"
require "set"

module EmTools
  module Plugins
    module GoogleAds
      module Catalog
        # Collects +source_product_id+ values present in an inventory index but absent from a
        # Google Ads catalog index for the same +source+ (e.g. AMZ_DE).
        class MissingProductIdsExporter
          DEFAULT_INVENTORY_INDEX = "em_inventory"
          DEFAULT_CATALOG_INDEX = "google_ads_products"
          DEFAULT_SOURCE_FIELD = "source"
          DEFAULT_ID_FIELD = "source_product_id"

          def initialize(es_client:, source:, inventory_index: DEFAULT_INVENTORY_INDEX,
            catalog_index: DEFAULT_CATALOG_INDEX, source_field: DEFAULT_SOURCE_FIELD,
            id_field: DEFAULT_ID_FIELD, logger: nil)
            @es = es_client
            @source = source.to_s.strip
            @inventory_index = inventory_index.to_s.strip
            @catalog_index = catalog_index.to_s.strip
            @source_field = source_field.to_s.strip
            @id_field = id_field.to_s.strip
            @logger = logger || EmTools::Core::Logger.for(progname: "google-ads-catalog")
          end

          # @param output_path [String]
          # @return [Hash] counts summary
          def export!(output_path)
            raise ArgumentError, "source is required (e.g. AMZ_DE)" if @source.empty?

            inventory_ids = collect_ids(@inventory_index)
            catalog_ids = collect_ids(@catalog_index)
            missing = inventory_ids - catalog_ids

            path = File.expand_path(output_path)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, format_file_body(missing))

            summary = {
              source: @source,
              inventory_index: @inventory_index,
              catalog_index: @catalog_index,
              inventory_ids: inventory_ids.size,
              catalog_ids: catalog_ids.size,
              missing_ids: missing.size,
              output_path: path,
            }
            @logger.info { summary.map { |k, v| "#{k}=#{v}" }.join(" ") }
            summary
          end

          private

          def collect_ids(index)
            raise ArgumentError, "index name is required" if index.empty?

            unless @es.index_exists?(index)
              raise EmTools::Core::Errors::ConfigurationError, "Elasticsearch index not found: #{index}"
            end

            seen = Set.new
            @es.iterate_query(index: index, query: build_query, batch_size: 2_000) do |hit|
              raw = extract_id(hit)
              next if raw.nil?

              id = raw.to_s.strip
              seen << id unless id.empty?
            end
            seen
          end

          def build_query
            { bool: { filter: [source_filter] } }
          end

          def source_filter
            variants = source_term_variants(@source)
            field = @source_field
            # Prefer .keyword subfield when the base name has no dot (typical text+keyword mapping).
            field = "#{field}.keyword" unless field.include?(".")

            { terms: { field => variants } }
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

          def format_file_body(ids)
            lines = [
              "# source: #{@source}",
              "# inventory_index: #{@inventory_index}",
              "# catalog_index: #{@catalog_index}",
              "# missing_count: #{ids.size}",
              "# id_field: #{@id_field}",
            ]
            ids.sort.each { |id| lines << id }
            "#{lines.join("\n")}\n"
          end
        end
      end
    end
  end
end
