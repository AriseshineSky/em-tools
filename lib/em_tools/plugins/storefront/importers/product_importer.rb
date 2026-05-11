# frozen_string_literal: true

require "json"

module EmTools
  module Plugins
    module Storefront
      module Importers
        class ProductImporter
          Result = Struct.new(
            :invalid_products,
            :blacklisted_products,
            :category_filtered_products,
            :price_filtered_products,
            :accepted_products,
            :batches_emitted,
            keyword_init: true,
          )

          def initialize(store_code:, batch_size: 50, min_price: 40, max_price: 500, blacklist_keywords: [],
            min_shipping_days: 7, taxonomy_name: "Categories", merchant_id: nil, vendor_id: nil, tax_category_id: 1, stock_location_id: nil, shipping_category_id: nil, dont_filter_blacklist: false, dont_optimize_title: false)
            @store_code = store_code.to_s.downcase
            @batch_size = [batch_size.to_i, 1].max
            @min_price = min_price
            @max_price = max_price
            @min_shipping_days = min_shipping_days
            @taxonomy_name = taxonomy_name
            @merchant_id = merchant_id
            @vendor_id = vendor_id
            @tax_category_id = tax_category_id
            @stock_location_id = stock_location_id
            @shipping_category_id = shipping_category_id
            @dont_filter_blacklist = dont_filter_blacklist
            @dont_optimize_title = dont_optimize_title
            @blacklist_keywords = Array(blacklist_keywords).map { |keyword| keyword.to_s.strip }.reject(&:empty?)
          end

          def process(file_path, output: $stdout)
            result = Result.new(
              invalid_products: 0,
              blacklisted_products: 0,
              category_filtered_products: 0,
              price_filtered_products: 0,
              accepted_products: 0,
              batches_emitted: 0,
            )

            batch = []
            File.open(file_path, encoding: "utf-8", errors: "ignore") do |fh|
              fh.each_line do |line|
                product = parse_product(line)
                unless product
                  result.invalid_products += 1
                  next
                end

                next unless accepted_product?(product, result)

                batch << normalized_product(product)
                result.accepted_products += 1

                next if batch.size < @batch_size

                emit_batch(batch, output)
                result.batches_emitted += 1
                batch = []
              end
            end

            if batch.any?
              emit_batch(batch, output)
              result.batches_emitted += 1
            end

            result
          end

          private

          def parse_product(line)
            payload = JSON.parse(line)
            return payload if payload.is_a?(Hash)

            nil
          rescue JSON::ParserError
            nil
          end

          def accepted_product?(product, result)
            if category_filtered?(product)
              result.category_filtered_products += 1
              return false
            end

            price = product["price"]
            unless price.is_a?(Numeric) || price.to_s.match?(/\A\d+(\.\d+)?\z/)
              result.price_filtered_products += 1
              return false
            end

            price = price.to_f
            if price < @min_price || price > @max_price
              result.price_filtered_products += 1
              return false
            end

            if blacklist_enabled? && blacklisted?(product)
              result.blacklisted_products += 1
              return false
            end

            true
          end

          def category_filtered?(product)
            categories = product["categories"]
            return false if categories.nil? || categories == ""

            categories = categories.split(">") if categories.is_a?(String)
            categories = Array(categories)
            root_category = categories.first.to_s
            return false if root_category.empty?

            blacklist_categories.each do |category|
              return true if @store_code.include?(category[:store]) && root_category.downcase.include?(category[:name])
            end

            false
          end

          def blacklist_categories
            [
              { store: "us", name: "gift cards" },
              { store: "uk", name: "auto" },
              { store: "uk", name: "kitchen" },
              { store: "uk", name: "guarden" },
              { store: "uk", name: "lawn" },
              { store: "uk", name: "toy" },
              { store: "ca", name: "auto" },
              { store: "ca", name: "kitchen" },
              { store: "ca", name: "guarden" },
              { store: "ca", name: "lawn" },
              { store: "ca", name: "toy" },
            ]
          end

          def blacklist_enabled?
            !@dont_filter_blacklist && @blacklist_keywords.any?
          end

          def blacklisted?(product)
            text = [product["brand"], product["title_en"], product["title"]].compact.join(" - ").downcase
            @blacklist_keywords.any? { |keyword| text.include?(keyword.downcase) }
          end

          def normalized_product(product)
            normalized = product.dup
            normalized.delete("categories")
            normalized
          end

          def emit_batch(batch, output)
            payload = build_batch_payload(batch)
            output.puts(JSON.generate(payload))
          end

          def build_batch_payload(products)
            {
              "store_code" => @store_code,
              "merchant_id" => @merchant_id,
              "vendor_id" => @vendor_id,
              "tax_category_id" => @tax_category_id,
              "stock_location_id" => @stock_location_id,
              "shipping_category_id" => @shipping_category_id,
              "min_shipping_days" => @min_shipping_days,
              "taxonomy_name" => @taxonomy_name,
              "dont_optimize_title" => @dont_optimize_title,
              "products" => products,
            }
          end
        end
      end
    end
  end
end
