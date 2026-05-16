# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module EmTools
  module Clients
    # Ruby port of +em_tasks/utils/exchange_rate.py::ExchangeRate+. Looks up an FX rate from
    # https://hexarate.paikama.co (the same service the Python code targets) with a 2 second
    # timeout, falling back to a hardcoded snapshot of rates against USD when the HTTP call
    # fails. Successful lookups are memoized in a class-level cache (+@@cached_rates+ in
    # Python; +@cached_rates+ on the singleton class here).
    #
    # Used by {EmTools::Plugins::Amazon::Uploadable::Transforms::PriceCalculator}, which mirrors
    # +em_tasks/utils/price_calculator.py+.
    class ExchangeRate
      DEFAULT_RATES = {
        "USD" => 1,
        "CAD" => 1.2874,
        "CNY" => 6.6093,
        "GBP" => 0.7414,
        "INR" => 90.18,
        "JPY" => 112.49,
        "MXN" => 18.674,
        "EUR" => 0.8414,
        "AUD" => 1.2994,
        "SGD" => 1.34811,
        "SAR" => 3.751579,
        "TRY" => 44.61,
        "KRW" => 1358.02,
        "AED" => 3.67,
      }.freeze

      DEFAULT_ENDPOINT = "https://hexarate.paikama.co/api/rates"
      DEFAULT_TIMEOUT_SECONDS = 2

      class << self
        # Returns the rate to multiply a +base_currency+ amount by to get a +currency+ amount.
        # Returns +1+ when both currencies are equal, the cached / fetched rate when found, or
        # +nil+ when neither HTTP nor the default table can answer.
        #
        # @param base_currency [String]
        # @param currency [String]
        # @param endpoint [String] hexarate path segment (default "latest").
        # @param http_client [#get_response, nil] override transport for tests; receives a +URI+.
        def get_exchange_rate(base_currency, currency, endpoint: "latest", http_client: nil)
          base = (base_currency || "USD").to_s.upcase
          target = (currency || "USD").to_s.upcase
          return 1 if base == target

          cache_key = [base, target]
          cached = cached_rates[cache_key]
          return cached if cached

          rate = fetch_remote_rate(base, target, endpoint, http_client) || fallback_rate(base, target)
          cached_rates[cache_key] = rate if rate
          rate
        end

        # Test hook: clear the memoized rate cache.
        def reset_cache!
          @cached_rates = {}
        end

        private

        def cached_rates
          @cached_rates ||= {}
        end

        def fetch_remote_rate(base, target, endpoint, http_client)
          uri = URI("#{DEFAULT_ENDPOINT}/#{base}/#{target}/#{endpoint}")
          response = perform_get(uri, http_client)
          return unless response && response.code.to_i == 200

          parsed = JSON.parse(response.body)
          parsed.dig("data", "mid")
        rescue StandardError
          nil
        end

        def perform_get(uri, http_client)
          return http_client.get_response(uri) if http_client

          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: DEFAULT_TIMEOUT_SECONDS,
            read_timeout: DEFAULT_TIMEOUT_SECONDS,
          ) do |http|
            http.request(Net::HTTP::Get.new(uri.request_uri))
          end
        rescue StandardError
          nil
        end

        def fallback_rate(base, target)
          if base == "USD"
            DEFAULT_RATES[target]
          elsif target == "USD"
            base_rate = DEFAULT_RATES[base]
            base_rate ? (1.0 / base_rate) : nil
          end
        end
      end
    end
  end
end
