# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Storefront
      module Cli
        # +em-tools storefront import-products INPUT_PATH+ — read NDJSON product feed,
        # filter invalid / blacklisted / price-ineligible items, emit batch payloads.
        class ImportProducts < Dry::CLI::Command
          desc "Filter NDJSON storefront products and emit batch payloads"

          argument :input_path, required: true, desc: "Path to a local NDJSON product feed"

          option :store_code, aliases: ["-s"], desc: "Store code (required)"
          option :keywords_path, desc: "Optional blacklist keywords file (txt or json)"
          option :output, aliases: ["-o"], desc: "Write batch payloads to file instead of stdout"
          option :batch_size, aliases: ["-b"], default: "50", desc: "Products per batch (default: 50)"
          option :min_price, default: "40", desc: "Minimum product price (default: 40)"
          option :max_price, default: "500", desc: "Maximum product price (default: 500)"
          option :min_shipping_days, default: "7", desc: "Minimum shipping days (default: 7)"
          option :taxonomy_name, default: "Categories", desc: "Taxonomy name (default: Categories)"
          option :merchant_id, desc: "Merchant id (preserved for adapter)"
          option :vendor_id, desc: "Vendor id (preserved for adapter)"
          option :tax_category_id, default: "1", desc: "Tax category id (default: 1)"
          option :stock_location_id, desc: "Stock location id"
          option :shipping_category_id, desc: "Shipping category id"
          option :dont_filter_blacklist, type: :flag, default: false, desc: "Disable blacklist filtering"
          option :dont_optimize_title, type: :flag, default: false, desc: "Preserve titles as-is"

          example [
            "products.ndjson -s MYSTORE",
            "products.ndjson -s MYSTORE --keywords-path tmp/blacklist.txt -o batches.ndjson",
          ]

          def call(input_path:, store_code: nil, keywords_path: nil, output: nil,
            batch_size: "50", min_price: "40", max_price: "500", min_shipping_days: "7",
            taxonomy_name: "Categories", merchant_id: nil, vendor_id: nil,
            tax_category_id: "1", stock_location_id: nil, shipping_category_id: nil,
            dont_filter_blacklist: false, dont_optimize_title: false, **)
            if store_code.to_s.strip.empty?
              warn("error: -s / --store-code is required")
              exit(1)
            end

            input = File.expand_path(input_path)
            unless File.file?(input)
              warn("error: input file not found: #{input}")
              exit(1)
            end

            keywords = keywords_path ? EmTools::Core::Cli::Support.load_keywords(keywords_path) : []
            io = output ? File.open(output, "w") : $stdout
            importer = EmTools::Core::PluginRegistry.fetch(:storefront).product_importer(
              store_code: store_code,
              batch_size: Integer(batch_size),
              min_price: Float(min_price),
              max_price: Float(max_price),
              blacklist_keywords: keywords,
              min_shipping_days: Integer(min_shipping_days),
              taxonomy_name: taxonomy_name,
              merchant_id: merchant_id,
              vendor_id: vendor_id,
              tax_category_id: Integer(tax_category_id),
              stock_location_id: stock_location_id ? Integer(stock_location_id) : nil,
              shipping_category_id: shipping_category_id ? Integer(shipping_category_id) : nil,
              dont_filter_blacklist: dont_filter_blacklist,
              dont_optimize_title: dont_optimize_title,
            )

            begin
              result = importer.process(input, output: io)
              warn("[ProductAudit] Invalid: #{result.invalid_products}, " \
                "CategoryFiltered: #{result.category_filtered_products}, " \
                "PriceFiltered: #{result.price_filtered_products}, " \
                "Blacklisted: #{result.blacklisted_products}, " \
                "Accepted: #{result.accepted_products}, " \
                "Batches: #{result.batches_emitted}")
            ensure
              io.close if output
            end
          end
          # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
        end
      end
    end
  end
end
