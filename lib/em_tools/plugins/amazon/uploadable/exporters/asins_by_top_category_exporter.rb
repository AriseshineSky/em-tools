# frozen_string_literal: true

require "fileutils"
require "json"

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Exporters
          # mget local ASINs from +amz_products_api_<mp>_v2+ (_id = ASIN) and write
          # +<output>/<marketplace>/<top_category>/asins.txt+ (one ASIN per line).
          class AsinsByTopCategoryExporter
            MGET_BATCH = 500
            ASINS_FILENAME = "asins.txt"
            UNCATEGORIZED = TopCategoryExtract::UNCATEGORIZED

            def initialize(es_client:, product_index:, output_dir:, marketplace:,
              category_from: :top_category, logger: nil)
              @es = es_client
              @product_index = product_index.to_s.strip
              @output_dir = File.expand_path(output_dir)
              @marketplace = marketplace.to_s.strip.downcase
              @category_from = category_from
              @logger = logger || EmTools::Core::Logger.for(progname: "amazon-products")
              @counts = Hash.new(0)
              @missing = 0
            end

            # @param input_path [String] local ASIN list
            # @return [Hash] summary
            def export!(input_path:)
              asins = EmTools::Core::Inventory::AsinListReader.read!(input_path)
              export_asins!(asins, source_label: File.expand_path(input_path))
            end

            # @param asins [Array<String>] ASIN / product ids (_id in product index)
            # @param source_label [String] recorded in manifest (file path or inventory query)
            # @return [Hash] summary
            def export_asins!(asins, source_label:)
              prepare_export!
              asins.each_slice(MGET_BATCH) { |batch| append_asins!(batch) }
              finalize_export!(source_label, asins.size)
            end

            # Append one mget batch to category files (for streaming inventory export).
            def append_asins!(asins)
              prepare_export! unless @prepared

              asins.each_slice(MGET_BATCH) do |batch|
                resp = @es.mget(index: @product_index, ids: batch)
                Array(resp["docs"]).each do |doc|
                  asin = doc["_id"].to_s
                  unless doc["found"]
                    @missing += 1
                    write_asin!(UNCATEGORIZED, asin)
                    next
                  end

                  category = TopCategoryExtract.resolve(doc["_source"], category_from: @category_from)
                  write_asin!(category, asin)
                end
              end
            end

            # @return [Hash] summary
            def finalize_export!(source_label, asin_count)
              write_manifest!(source_label, asin_count)
              summary = {
                source: source_label.to_s,
                product_index: @product_index,
                marketplace: @marketplace,
                output_dir: @output_dir,
                asins: asin_count,
                missing: @missing,
                categories: @counts.size,
                manifest_path: File.join(@output_dir, @marketplace, "manifest.json"),
              }
              @logger.info { summary.map { |k, v| "#{k}=#{v}" }.join(" ") }
              summary
            end

            def self.index_for_marketplace(marketplace)
              TopCategoryAsinExporter.index_for_marketplace(marketplace)
            end

            def self.marketplace_from_sold_filename(path)
              base = File.basename(path.to_s, ".*")
              mp = base.sub(/\AAMZ_/i, "").strip.downcase
              raise ArgumentError, "cannot infer marketplace from filename: #{path.inspect}" if mp.empty?

              mp
            end

            private

            def prepare_export!
              return if @prepared

              raise ArgumentError, "product_index is required" if @product_index.empty?
              raise ArgumentError, "marketplace is required" if @marketplace.empty?

              unless @es.index_exists?(@product_index)
                raise EmTools::Core::Errors::ConfigurationError,
                  "Elasticsearch index not found: #{@product_index}"
              end

              @counts = Hash.new(0)
              @missing = 0
              @prepared = true
              base = File.join(@output_dir, @marketplace)
              FileUtils.mkdir_p(base)
            end

            def write_asin!(category, asin)
              path = category_file_path(category)
              FileUtils.mkdir_p(File.dirname(path))
              File.open(path, "a") { |f| f.puts(asin) }
              @counts[category] += 1
            end

            def category_file_path(category)
              File.join(@output_dir, @marketplace, safe_dirname(category), ASINS_FILENAME)
            end

            def write_manifest!(source_label, asin_count)
              manifest_path = File.join(@output_dir, @marketplace, "manifest.json")
              FileUtils.mkdir_p(File.dirname(manifest_path))
              manifest = {
                "source" => source_label.to_s,
                "product_index" => @product_index,
                "marketplace" => @marketplace,
                "category_from" => @category_from.to_s,
                "asins" => asin_count,
                "missing" => @missing,
                "categories" => @counts.sort_by { |cat, _| cat }.map do |cat, count|
                  {
                    "name" => cat,
                    "count" => count,
                    "dir" => File.join(@marketplace, safe_dirname(cat)),
                    "file" => ASINS_FILENAME,
                  }
                end,
              }
              File.write(manifest_path, JSON.pretty_generate(manifest))
            end

            def safe_dirname(name)
              base = name.to_s.strip
              base = UNCATEGORIZED if base.empty?
              base.gsub(/[\/\\:*?"<>|]/, "_").gsub(/\s+/, " ").strip.slice(0, 120)
            end
          end
        end
      end
    end
  end
end
