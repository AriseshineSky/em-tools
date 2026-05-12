# frozen_string_literal: true

require "optparse"

module EmTools
  module Plugins
    module Storefront
      module Cli
        class ImportProducts
          def run(argv)
            options = {
              store_code: nil,
              min_price: 40,
              max_price: 500,
              batch_size: 50,
              min_shipping_days: 7,
              taxonomy_name: "Categories",
              merchant_id: nil,
              vendor_id: nil,
              tax_category_id: 1,
              stock_location_id: nil,
              shipping_category_id: nil,
              dont_filter_blacklist: false,
              dont_optimize_title: false,
              keywords_path: nil,
              output_path: nil,
            }

            # -- many CLI flags for storefront:import-products
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools storefront:import-products [options] INPUT_PATH

                Read NDJSON products, filter invalid/blacklisted/price-ineligible items,
                and emit batch payloads as NDJSON.

                This first version preserves the import shape for a later Spree adapter.
              BANNER

              opts.on("-s", "--store-code CODE", String, "Store code, required.") do |value|
                options[:store_code] = value
              end
              opts.on("--keywords-path PATH", String, "Optional blacklist keywords file (txt or json).") do |value|
                options[:keywords_path] = value
              end
              opts.on("-o", "--output PATH", String, "Write batch payloads to file instead of stdout.") do |value|
                options[:output_path] = value
              end
              opts.on("-b", "--batch-size N", Integer, "Products per batch (default: 50).") do |value|
                options[:batch_size] = value
              end
              opts.on("--min-price N", Float, "Minimum product price (default: 40).") do |value|
                options[:min_price] = value
              end
              opts.on("--max-price N", Float, "Maximum product price (default: 500).") do |value|
                options[:max_price] = value
              end
              opts.on("--min-shipping-days N", Integer, "Minimum shipping days (default: 7).") do |value|
                options[:min_shipping_days] = value
              end
              opts.on("--taxonomy-name NAME", String, "Taxonomy name (default: Categories).") do |value|
                options[:taxonomy_name] = value
              end
              opts.on("--merchant-id ID", String, "Merchant id, preserved for later adapter.") do |value|
                options[:merchant_id] = value
              end
              opts.on("--vendor-id ID", String, "Vendor id, preserved for later adapter.") do |value|
                options[:vendor_id] = value
              end
              opts.on("--tax-category-id ID", Integer, "Tax category id (default: 1).") do |value|
                options[:tax_category_id] = value
              end
              opts.on("--stock-location-id ID", Integer, "Stock location id.") do |value|
                options[:stock_location_id] = value
              end
              opts.on("--shipping-category-id ID", Integer, "Shipping category id.") do |value|
                options[:shipping_category_id] = value
              end
              opts.on("--dont-filter-blacklist", "Disable blacklist filtering.") do
                options[:dont_filter_blacklist] = true
              end
              opts.on("--dont-optimize-title", "Preserve the title as-is.") { options[:dont_optimize_title] = true }
            end
            # rubocop:enable Metrics/BlockLength

            parser.parse!(argv)
            input_arg = argv.shift
            usage!(parser) unless input_arg

            unless argv.empty?
              warn("error: unexpected arguments: #{argv.join(" ")}")
              usage!(parser)
            end

            if options[:store_code].to_s.strip.empty?
              warn("error: --store-code is required")
              exit(1)
            end

            input_path = File.expand_path(input_arg)
            unless File.file?(input_path)
              warn("error: input file not found: #{input_path}")
              exit(1)
            end

            keywords = options[:keywords_path] ? Support.load_keywords(options[:keywords_path]) : []
            out = options[:output_path] ? File.open(options[:output_path], "w") : $stdout
            importer = EmTools::Plugins::Storefront::Importers::ProductImporter.new(
              store_code: options[:store_code],
              batch_size: options[:batch_size],
              min_price: options[:min_price],
              max_price: options[:max_price],
              blacklist_keywords: keywords,
              min_shipping_days: options[:min_shipping_days],
              taxonomy_name: options[:taxonomy_name],
              merchant_id: options[:merchant_id],
              vendor_id: options[:vendor_id],
              tax_category_id: options[:tax_category_id],
              stock_location_id: options[:stock_location_id],
              shipping_category_id: options[:shipping_category_id],
              dont_filter_blacklist: options[:dont_filter_blacklist],
              dont_optimize_title: options[:dont_optimize_title],
            )

            begin
              result = importer.process(input_path, output: out)
              warn("[ProductAudit] Invalid: #{result.invalid_products}, " \
                "CategoryFiltered: #{result.category_filtered_products}, " \
                "PriceFiltered: #{result.price_filtered_products}, " \
                "Blacklisted: #{result.blacklisted_products}, " \
                "Accepted: #{result.accepted_products}, " \
                "Batches: #{result.batches_emitted}")
            ensure
              out.close if options[:output_path]
            end
          end

          private

          def usage!(parser)
            warn(parser.help)
            exit(1)
          end
        end
      end
    end
  end
end
