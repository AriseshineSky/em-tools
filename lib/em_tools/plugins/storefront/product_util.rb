# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'json'
require 'securerandom'
require 'tmpdir'

module EmTools
  module Plugins
    module Storefront
      # Higher-level product/inventory helpers built on top of {EmTools::Plugins::Storefront::Api}.
      # rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Naming/AccessorMethodName -- mirror em-tasks' ProductUtil API for migration compatibility.
      class ProductUtil
        INVENTORY_HEADERS = {
          'ProductID' => 'product_id',
          'Source' => 'source',
          'SourceProductID' => 'source_product_id',
          'Handle' => 'handle',
          'Variants' => 'variants',
          'InStock' => 'in_stock'
        }.freeze

        DOWNLOAD_HEADERS = INVENTORY_HEADERS.except('InStock').freeze

        attr_reader :spree_api

        def initialize(endpoint, api_key, api_version: 'v1', spree_api: nil, logger: nil)
          @spree_api = spree_api || EmTools::Clients::SpreeClient.new(
            endpoint, api_key, api_version: api_version, logger: logger
          )
          @logger = logger
        end

        def get_daisomall_products(&block)
          get_products('Daisomall', &block)
        end

        def get_yesstyle_products(&block)
          return enum_for(__method__) unless block

          get_products('Yeskr', &block)
          get_products('Yesjp', &block)
        end

        def get_hepsiburada_products(&block)
          get_products('Hepsiburada', &block)
        end

        def get_trendyol_products(marketplace = 'us', &block)
          get_products('Trendyol', marketplace, &block)
        end

        def get_amz_products(marketplace = 'us', &block)
          get_products('Amazon', marketplace, &block)
        end

        def get_alibaba_products(&block)
          get_products('Alibaba', &block)
        end

        def get_emp_products(&block)
          get_products('EMP', &block)
        end

        def get_boots_products(&block)
          get_products('Boots', &block)
        end

        def get_ebay_products(marketplace = 'us', &block)
          get_products('Ebay', marketplace, &block)
        end

        def get_nandansons_products(&block)
          get_products('nandansons', &block)
        end

        def get_rakuten_products(&block)
          get_products('Rakuten', &block)
        end

        def get_st11_products(&block)
          get_products('11ST', &block)
        end

        def get_apo_health_products(&block)
          get_products('ApoHealth', &block)
        end

        def get_lotteon_products(&block)
          get_products('lotteon', &block)
        end

        def get_wemakeprice_products(&block)
          get_products('WEMAKEPRICE', &block)
        end

        def get_naver_products(&block)
          get_products('Naver', &block)
        end

        def get_dangdang_products(&block)
          get_products('Dangdang', &block)
        end

        def get_coupang_products(&block)
          get_products('Coupang', &block)
        end

        def get_faire_products(&block)
          get_products('faire', &block)
        end

        def get_www_books_com_tw_products(&block)
          get_products('www_books_com_tw', &block)
        end

        def get_products(src, marketplace = nil, &block)
          return enum_for(__method__, src, marketplace) unless block

          source = inventory_source(src, marketplace)
          return if source.nil?

          output_path = File.join(Dir.tmpdir, "#{source}-#{SecureRandom.uuid}.csv")
          begin
            log(:info, '[InventoryPath] %s', output_path)
            spree_api.download_inventory(source, output_path)
            return unless File.file?(output_path)

            get_products_from_inv_file(output_path, &block)
          ensure
            FileUtils.rm_f(output_path)
          end
        end

        def get_products_from_inv_file(inv_path, &block)
          return enum_for(__method__, inv_path) unless block

          each_inventory_record(inv_path, INVENTORY_HEADERS, require_core_fields: true, &block)
        end

        def get_multi_sources_products(source)
          products = {}
          page = 0
          per_page = 100
          total_pages = 1

          while page < total_pages
            begin
              page += 1
              result = spree_api.get_multi_source_products(source, page, per_page)
              break if api_error_result?(result)

              total_pages = result.fetch('total_pages')
              Array(result['products']).each { |product| products[product['id']] = product }
            rescue StandardError => e
              log_exception(e)
            end
          end

          products
        end

        def get_manual_products
          result = spree_api.get_manual_products
          return [] if api_error_result?(result)

          Array(result['products'])
        rescue StandardError => e
          log_exception(e)
          []
        end

        def set_products_offer(prods, _pool = nil)
          store_offers = {}
          prods.each do |prod_id, prod|
            prod = stringify_keys(prod)
            variants = Array(prod['variants'])
            next if variants.empty?

            offer = prod['offer']
            next if offer == false || offer.nil?

            offer = stringify_nested_hash(offer)
            next if variants.length > 1 && !offer.is_a?(Hash)

            store_offer = build_store_offer(prod_id, prod, variants, offer)
            store_offers[prod_id] = store_offer
          end

          resp = spree_api.set_offers(store_offers)
          log(:info, '[InventoryUpdated] %s', resp)
          store_offers
        end

        def set_inventory(stock_items)
          succeed = true

          stock_items.each do |stock_item|
            succeed = false unless update_stock_item(stock_item)
          end

          succeed
        end

        def set_price(product_id, variant_id, price, cost = nil)
          retries = 3
          loop do
            resp = if cost
                     spree_api.update_variant(product_id, variant_id, price: price, cost_price: cost)
                   else
                     spree_api.update_variant(product_id, variant_id, price: price)
                   end
            if response_code(resp) == 422 && (retries -= 1).positive?
              log(:debug, '[PriceUpdateMsg] ProductID: %s, VariantId: %s, Price: %s, Response: %s',
                  product_id, variant_id, price, response_body(resp))
              sleep 1
              next
            end

            return handle_price_response(resp, product_id, variant_id, price)
          rescue StandardError => e
            log(:warning, '[PriceUpdateError] ProductId: %s, VariantId: %s, Price: %s', product_id, variant_id, price)
            log_exception(e)
            return false unless (retries -= 1).positive?
          end
        end

        def download_inventory(source, output_path, &block)
          return enum_for(__method__, source, output_path) unless block

          spree_api.download_inventory(source, output_path)
          return unless File.file?(output_path)

          each_inventory_record(output_path, DOWNLOAD_HEADERS, require_core_fields: false, &block)
        end

        private

        def inventory_source(src, marketplace)
          case src
          when 'Amazon'
            marketplace ? "AMZ_#{marketplace.to_s.upcase}" : src
          when 'Ebay'
            marketplace ? "Ebay_#{marketplace.to_s.upcase}" : src
          else
            src
          end
        end

        def each_inventory_record(inv_path, headers_mapping, require_core_fields:)
          CSV.foreach(inv_path, headers: true, encoding: 'bom|utf-8:UTF-8', invalid: :replace, undef: :replace) do |row|
            record = inventory_record(row, headers_mapping)
            next if record.empty?
            next if require_core_fields && missing_core_inventory_fields?(record)

            yield record
          rescue StandardError => e
            log(:info, '[InventoryRow] %s', row&.fields)
            log_exception(e)
          end
        end

        def inventory_record(row, headers_mapping)
          headers_mapping.each_with_object({}) do |(csv_header, record_header), acc|
            next unless row.headers.include?(csv_header)

            value = row[csv_header]
            acc[record_header] = record_header == 'variants' ? JSON.parse(value.to_s) : value
          end
        end

        def missing_core_inventory_fields?(record)
          record['product_id'].to_s.empty? ||
            record['source'].to_s.empty? ||
            record['source_product_id'].to_s.empty?
        end

        def build_store_offer(prod_id, prod, variants, offer)
          offer = normalize_single_variant_offer(variants, offer)
          store_offer = { 'handle' => prod['handle'], 'product_id' => prod_id, 'offers' => {} }

          variants.each do |variant|
            variant = stringify_keys(variant)
            variant_id = variant['variant_id']
            v_offer = offer[variant_id]
            next unless v_offer

            target_offer = build_variant_offer(prod_id, variant_id, stringify_keys(v_offer))
            store_offer['offers'][variant_id] = target_offer
            log(:debug, '[InventoryUpdate] ProductId: %s, VariantId: %s, Price: %s, Quantity: %s',
                prod_id, variant_id, target_offer['price'], target_offer['quantity'])
          end

          store_offer
        end

        def normalize_single_variant_offer(variants, offer)
          return offer unless variants.length == 1

          variant_id = stringify_keys(variants.first)['variant_id']
          offer.key?(variant_id) ? offer : { variant_id => offer }
        end

        def build_variant_offer(prod_id, variant_id, v_offer)
          price = round_two(v_offer.fetch('price'))
          quantity = round_two(v_offer.fetch('quantity'))
          currency = v_offer.fetch('currency', 'USD')
          target_offer = {
            'product_id' => prod_id,
            'variant_id' => variant_id,
            'price' => price,
            'quantity' => quantity,
            'currency' => currency
          }

          if quantity.positive? && v_offer.key?('src_price')
            target_offer['cost_price'] = round_two(v_offer['src_price'])
            target_offer['cost_currency'] = currency
          end
          target_offer
        end

        def update_stock_item(stock_item)
          item = stringify_keys(stock_item)
          retries = 3

          loop do
            resp = spree_api.update_stock(item['id'], item['quantity'], item['stock_location_id'])
            if response_code(resp) == 422 && (retries -= 1).positive?
              log(:debug, '[StockUpdateMsg] VariantId: %s, Stock: %s, Quantity: %s, Response: %s',
                  item['variant_id'], item['id'], item['quantity'], response_body(resp))
              sleep 1
              next
            end

            return handle_stock_response(resp, item)
          rescue StandardError => e
            log_exception(e)
            return false unless (retries -= 1).positive?

            sleep 1
          end
        end

        def handle_stock_response(resp, item)
          stock = parse_response_json(resp)
          if response_error_result?(stock)
            log(:warning, '[StockUpdateError] VariantId: %s, Stock: %s, Error: %s',
                item['variant_id'], item['id'], stock['error'] || stock['errors'])
            false
          else
            log(:info, '[StockUpdated] VariantId: %s, Stock: %s, Quantity: %s',
                item['variant_id'], item['id'], item['quantity'])
            true
          end
        rescue StandardError => e
          log_exception(e)
          log(:warning, '[StockUpdateInvalidResponse] %s', response_body(resp))
          false
        end

        def handle_price_response(resp, product_id, variant_id, price)
          variant = parse_response_json(resp)
          if response_error_result?(variant)
            log(:warning, '[PriceUpdateError] ProductId: %s, VariantId: %s, Error: %s',
                product_id, variant_id, variant['error'] || variant['errors'])
            false
          elsif variant['sku'].to_s.empty?
            log(:info, '[ResponseWithoutSKU] %s', response_body(resp))
            true
          else
            log(:info, '[PriceUpdated] ProductId: %s, VariantId: %s, Price: %s, SKU: %s',
                product_id, variant_id, price, variant['sku'])
            true
          end
        rescue StandardError
          log(:warning, '[PriceUpdateInvalidResponse] %s', response_body(resp))
          false
        end

        def api_error_result?(result)
          result.nil? || response_error_result?(result)
        end

        def response_error_result?(result)
          result.is_a?(Hash) && (result.key?('error') || result.key?('errors'))
        end

        def parse_response_json(resp)
          return resp.json if resp.respond_to?(:json)

          JSON.parse(response_body(resp).to_s)
        end

        def response_code(resp)
          return resp.status_code.to_i if resp.respond_to?(:status_code)
          return resp.code.to_i if resp.respond_to?(:code)

          0
        end

        def response_body(resp)
          return resp.text if resp.respond_to?(:text)
          return resp.body if resp.respond_to?(:body)

          resp.to_s
        end

        def round_two(value)
          value.to_f.round(2)
        end

        def stringify_nested_hash(value)
          case value
          when Hash
            value.each_with_object({}) { |(key, val), acc| acc[key.to_s] = stringify_nested_hash(val) }
          when Array
            value.map { |item| stringify_nested_hash(item) }
          else
            value
          end
        end

        def stringify_keys(hash)
          hash.each_with_object({}) { |(key, value), acc| acc[key.to_s] = value }
        end

        def log(level, message, *args)
          @logger&.public_send(level, message, *args)
        end

        def log_exception(error)
          if @logger.respond_to?(:exception)
            @logger.exception(error)
          else
            log(:warning, '%s: %s', error.class, error.message)
          end
        end
      end
      # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Naming/AccessorMethodName
    end
  end
end
