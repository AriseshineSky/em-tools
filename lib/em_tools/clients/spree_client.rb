# frozen_string_literal: true

require "cgi"
require "fileutils"
require "json"
require "net/http"
require "uri"

module EmTools
  module Clients
    # rubocop:disable Naming/AccessorMethodName -- preserve the external API shape from the Python client.
    class SpreeClient
      RETRY_STATUSES = [429, 500, 502, 503, 504].freeze
      JSON_CONTENT_TYPE = "application/json"

      attr_reader :endpoint, :api_key, :api_version

      def initialize(endpoint, api_key, api_version: "v1", logger: nil, transport: nil,
        retries: 7, backoff_factor: 0.1, open_timeout: 60, read_timeout: 60)
        @endpoint = endpoint.to_s.sub(%r{/+\z}, "")
        @api_key = api_key
        @api_version = api_version
        @logger = logger || EmTools::Core::Logger.for(progname: "spree-client")
        @transport = transport || NetHttpTransport.new
        @retries = retries.to_i
        @backoff_factor = backoff_factor.to_f
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def list_orders(params = {})
        payload = {
          "token" => api_key,
          "q[completed_at_not_null]" => 1,
          "q[s]" => "completed_at:asc",
          "page" => 1,
          "per_page" => 50,
        }.merge(stringify_keys(params))

        json_request(:get, api_path("orders"), query: payload)
      end

      def get_orders(order_ids)
        json_request(
          :get,
          api_path("orders"),
          query: {
            "token" => api_key,
            "q[id_in][]" => order_ids,
            "q[s]" => "completed_at:asc",
            "page" => 1,
            "per_page" => order_ids.length,
          },
        )
      end

      def approve_order(order_number)
        json_request(:put, api_path("orders/#{escape_path(order_number)}/approve.json"), query: token_query)
      end

      def get_order_refunds(order_number)
        json_request(:get, api_path("orders/#{escape_path(order_number)}/refunds.json"), query: token_query)
      end

      def add_shipment_tracking(shipment_id, carrier, tracking, cost = nil)
        payload = {
          "shipment" => {
            "tracking" => tracking,
            "carrier" => carrier,
          },
        }
        payload["shipment"]["actual_cost"] = cost if cost

        json_request(
          :put,
          api_path("shipments/#{escape_path(shipment_id)}/ship"),
          query: token_query,
          json: payload,
        )
      end

      def update_stock(stock_item_id, qty, stock_location_id = 1, force: true, backorderable: false)
        request(
          :put,
          api_path("stock_locations/#{escape_path(stock_location_id)}/stock_items/#{escape_path(stock_item_id)}"),
          query: token_query,
          json: {
            "stock_item" => {
              "count_on_hand" => qty,
              "force" => force,
              "backorderable" => backorderable,
            },
          },
        )
      end

      def update_variant(product_id, variant_id, **params)
        request(
          :put,
          api_path("products/#{escape_path(product_id)}/variants/#{escape_path(variant_id)}"),
          query: token_query,
          json: { "variant" => stringify_keys(params) },
        )
      end

      def download_inventory(source, output_path)
        return if output_path.to_s.empty?

        prepare_output_path(output_path)
        uri = build_uri(api_path("inventory_reports/download"), token_query.merge("source" => source))
        http_request = build_request(:get, uri, nil)
        log_request(uri)
        response = perform_download_with_retries(uri, http_request, output_path)
        raise HttpError, "Spree API failed: #{response.code} #{response.message}" unless success?(response)

        nil
      end

      def get_multi_source_products(source, page, per_page)
        json_request(
          :get,
          api_path("products/get_multi_sources"),
          query: token_query.merge("source" => source, "page" => page, "per_page" => per_page),
        )
      end

      def get_manual_products
        json_request(:get, api_path("inventory_reports/download_manual_products"), query: token_query)
      end

      def set_offers(product_offers)
        json_request(
          :post,
          api_path("products/set_offers"),
          query: token_query,
          json: { "offers" => product_offers },
        )
      end

      def add_fulfill_orders(fulfill_orders)
        json_request(
          :post,
          api_path("fulfill_orders"),
          query: token_query,
          json: { "fulfill_orders" => fulfill_orders },
        )
      end

      def import_products(products, stock_location_id, shipping_category_id, vendor_id, merchant_id,
        min_shipping_days: 7, taxonomy_name: "Categories", tax_category_id: 1)
        json_request(
          :post,
          api_path("products/import"),
          query: token_query,
          json: {
            "products" => products,
            "min_shipping_days" => min_shipping_days,
            "taxonomy_name" => taxonomy_name,
            "merchant_id" => merchant_id,
            "vendor_id" => vendor_id,
            "tax_category_id" => tax_category_id,
            "stock_location_id" => stock_location_id,
            "shipping_category_id" => shipping_category_id,
          },
        )
      end

      def update_product(product_id, product)
        json_request(
          :put,
          api_path("products/#{escape_path(product_id)}"),
          query: token_query,
          json: { "product" => product },
        )
      end

      def delete_products(product_ids)
        json_request(
          :post,
          api_path("products/batch_delete"),
          query: token_query,
          json: { "product_ids" => product_ids.join(",") },
        )
      end

      def list_inventories(page: 1, per_page: 250, since_id: nil, **kwargs)
        payload = {
          "token" => api_key,
          "per_page" => per_page,
          "q[s]" => "id:asc",
        }
        if since_id
          payload["q[id_gt]"] = since_id
        else
          payload["page"] = page
        end
        payload.merge!(stringify_keys(kwargs))

        response = request(:get, api_path("inventories"), query: payload)
        parse_json(response.body)
      rescue JSON::ParserError
        response.body
      end

      def set_gmc_custom_labels(merchant_id, items)
        entries = Array(items).filter_map do |item|
          entry = stringify_keys(item)
          next unless entry.key?("item_id")

          entry["merchant_id"] = merchant_id unless entry.key?("merchant_id")
          entry
        end
        return if entries.empty?

        json_request(
          :post,
          api_path("gmc/set-custom-labels"),
          query: token_query,
          json: { "entries" => entries },
        )
      end

      def get_shop
        resp = json_request(:get, "/api/v1/stores", query: token_query)
        stores = Array(resp["stores"])
        return if stores.empty?

        stores.find { |store| store["default"] } || stores.first
      end

      private

      def json_request(method, path, query: {}, json: nil)
        parse_json(request(method, path, query: query, json: json).body)
      end

      def request(method, path, query: {}, json: nil)
        uri = build_uri(path, query)
        http_request = build_request(method, uri, json)
        log_request(uri)
        perform_with_retries(uri, http_request)
      end

      def build_uri(path, query)
        uri = URI.parse("#{endpoint}#{path}")
        uri.query = URI.encode_www_form(query) unless query.empty?
        uri
      end

      def build_request(method, uri, json)
        klass = request_class(method)
        req = klass.new(uri)
        return req if json.nil?

        req["Content-Type"] = JSON_CONTENT_TYPE
        req.body = JSON.generate(json)
        req
      end

      def perform_with_retries(uri, http_request)
        attempts = 0

        begin
          attempts += 1
          response = @transport.request(
            uri,
            http_request,
            open_timeout: @open_timeout,
            read_timeout: @read_timeout,
          )
          return response unless retry_response?(response) && attempts <= @retries

          @logger&.warn { "[RetryStatus] #{uri} status=#{response.code} attempt=#{attempts}/#{@retries}" }
          sleep(backoff_sleep(attempts))
        rescue IOError, SystemCallError, Timeout::Error => e
          raise if attempts > @retries

          log_retry(uri, e)
          sleep(backoff_sleep(attempts))
          retry
        end
      end

      def perform_download_with_retries(uri, http_request, output_path)
        attempts = 0

        begin
          attempts += 1
          response = @transport.download(
            uri,
            http_request,
            output_path,
            open_timeout: @open_timeout,
            read_timeout: @read_timeout,
          )
          return response unless retry_response?(response) && attempts <= @retries

          FileUtils.rm_f(output_path)
          sleep(backoff_sleep(attempts))
        rescue IOError, SystemCallError, Timeout::Error => e
          FileUtils.rm_f(output_path)
          raise if attempts > @retries

          log_retry(uri, e)
          sleep(backoff_sleep(attempts))
          retry
        end
      end

      def request_class(method)
        {
          get: Net::HTTP::Get,
          post: Net::HTTP::Post,
          put: Net::HTTP::Put,
          delete: Net::HTTP::Delete,
        }.fetch(method.to_sym)
      end

      def retry_response?(response)
        RETRY_STATUSES.include?(response.code.to_i)
      end

      def success?(response)
        response.code.to_i.between?(200, 299)
      end

      def backoff_sleep(attempts)
        @backoff_factor * (2**(attempts - 1))
      end

      def parse_json(body)
        JSON.parse(body.to_s)
      end

      def log_request(uri)
        @logger&.debug { "[Request] #{uri}" }
      end

      def log_retry(uri, error)
        @logger&.warn { "[Retry] #{uri} #{error.class}: #{error.message}" }
      end

      def token_query
        { "token" => api_key }
      end

      def api_path(path)
        "/api/#{api_version}/#{path}"
      end

      def escape_path(value)
        CGI.escape(value.to_s)
      end

      def prepare_output_path(output_path)
        output_dir = File.dirname(output_path)
        FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)
        FileUtils.rm_f(output_path)
      end

      def stringify_keys(hash)
        hash.each_with_object({}) { |(key, value), acc| acc[key.to_s] = value }
      end

      class HttpError < StandardError; end

      class NetHttpTransport
        def request(uri, request, open_timeout:, read_timeout:)
          Net::HTTP.start(
            uri.hostname,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: open_timeout,
            read_timeout: read_timeout,
          ) { |http| http.request(request) }
        end

        def download(uri, request, output_path, open_timeout:, read_timeout:)
          Net::HTTP.start(
            uri.hostname,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: open_timeout,
            read_timeout: read_timeout,
          ) do |http|
            http.request(request) do |response|
              if response.code.to_i.between?(200, 299)
                File.open(output_path, "wb") { |file| response.read_body { |chunk| file.write(chunk) } }
              else
                response.read_body { |_chunk| }
              end
              response
            end
          end
        end
      end
    end
    # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Naming/AccessorMethodName
  end
end
