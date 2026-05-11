# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module EmTools
  module Core
    module Blacklist
      # Downloads the keyword blacklist from the Everymarket admin API.
      #
      # Configuration is .env-only (never YAML):
      #
      #   * +BLACKLIST_API_ENDPOINT+ - scheme+host, e.g. +https://api.everymarket.com+.
      #   * +BLACKLIST_API_PATH+     - request path, e.g. +/api/v1/blacklist_keywords+.
      #   * +BLACKLIST_API_TOKEN+    - bearer token (also accepted via legacy +BLACKLIST_API_KEY+).
      #
      # The remote endpoint is paginated by an opaque integer +cursor+ and announces +has_more+
      # / +next_cursor+ on every page. Three consumption styles:
      #
      #   loader = EmTools::Core::Blacklist::Loader.new
      #   loader.each_page { |page| ... }   # streamed Hash per page; nice for --raw
      #   loader.fetch_pages                # Array<Hash>, all pages materialised
      #   loader.fetch_keywords             # Array<String>, flat unique keyword list
      #
      # The keyword extractor accepts the legacy +{"blacklist_keywords":[{"keywords": ...}]}+
      # shape and several flatter variants so a schema change on the server side does not silently
      # produce an empty list.
      class Loader
        DEFAULT_OPEN_TIMEOUT = 5
        DEFAULT_READ_TIMEOUT = 30
        # Hard ceiling so a buggy +has_more+ flag can never spin a job forever.
        # 200 pages * 1000 keywords/page is far above any realistic blacklist size.
        MAX_PAGES = 200

        # @param endpoint [String, nil]   overrides +BLACKLIST_API_ENDPOINT+.
        # @param path [String, nil]       overrides +BLACKLIST_API_PATH+.
        # @param token [String, nil]      overrides +BLACKLIST_API_TOKEN+.
        # @param open_timeout [Integer]   TCP connect timeout in seconds.
        # @param read_timeout [Integer]   response read timeout in seconds.
        # @param max_pages [Integer]      pagination safety ceiling.
        # @param logger [::Logger, nil]
        def initialize(endpoint: nil, path: nil, token: nil,
          open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
          max_pages: MAX_PAGES, logger: nil)
          @endpoint = endpoint || EmTools::Core::Config.blacklist_api_endpoint
          @path = path || EmTools::Core::Config.blacklist_api_path
          @token = token || EmTools::Core::Config.blacklist_api_token
          @open_timeout = open_timeout
          @read_timeout = read_timeout
          @max_pages = max_pages
          @logger = logger || EmTools::Core::Logger.for(progname: "blacklist")
        end

        # Stream pages until the server reports +has_more=false+ (or +MAX_PAGES+ is hit).
        # Yields each decoded page Hash. Returns an Enumerator when no block is given.
        def each_page
          return enum_for(:each_page) unless block_given?

          validate_config!
          cursor = nil
          page_count = 0

          loop do
            page = fetch_page(cursor)
            page_count += 1
            yield page

            # Non-Hash payloads (bare arrays, scalars) cannot carry pagination metadata, so
            # we treat any single response that isn't a Hash as terminal.
            break unless page.is_a?(Hash)

            next_cursor = page["next_cursor"]
            break unless page["has_more"] && next_cursor && next_cursor != cursor
            break if page_count >= @max_pages

            cursor = next_cursor
          end

          @logger.info { "[done] pages=#{page_count}" }
        end

        # @return [Array<Hash>] every page body in order. Heavy: holds the whole list in memory.
        def fetch_pages
          each_page.to_a
        end

        # @return [Hash] the first page only. Kept for backward-compat callers that only
        #   want a quick smoke-test of the auth + schema.
        def fetch
          validate_config!
          fetch_page(nil)
        end

        # @return [Array<String>] flat, deduplicated, non-blank keyword list across all pages.
        def fetch_keywords
          keywords = each_page.flat_map { |page| extract_keywords(page) }
          keywords.map { |kw| kw.to_s.strip }.reject(&:empty?).uniq
        end

        private

        def validate_config!
          missing = []
          missing << "BLACKLIST_API_ENDPOINT" if blank?(@endpoint)
          missing << "BLACKLIST_API_TOKEN"    if blank?(@token)
          return if missing.empty?

          raise EmTools::Core::Errors::ConfigurationError,
            "Blacklist API not configured: missing #{missing.join(", ")}"
        end

        def fetch_page(cursor)
          uri = build_uri(cursor)
          @logger.info { "[fetch] GET #{redact(uri)}" }
          body = perform_get(uri)
          JSON.parse(body)
        rescue JSON::ParserError => e
          raise EmTools::Core::Errors::ConfigurationError,
            "Blacklist API returned non-JSON body (#{e.message}); first 200 bytes: #{body.to_s[0, 200].inspect}"
        end

        def build_uri(cursor)
          base = URI.parse(@endpoint)
          unless base.is_a?(URI::HTTP)
            raise EmTools::Core::Errors::ConfigurationError,
              "BLACKLIST_API_ENDPOINT must be an http(s) URL, got: #{@endpoint.inspect}"
          end

          uri = @path.to_s.empty? ? base : URI.join(base.to_s, @path)
          params = { token: @token }
          params[:cursor] = cursor if cursor
          uri.query = URI.encode_www_form(params)
          uri
        end

        def perform_get(uri)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")
          http.open_timeout = @open_timeout
          http.read_timeout = @read_timeout

          req = Net::HTTP::Get.new(uri.request_uri)
          req["Authorization"] = "Bearer #{@token}"
          req["Accept"] = "application/json"

          res = http.request(req)
          unless res.code.to_i.between?(200, 299)
            raise EmTools::Core::Errors::ConfigurationError,
              "Blacklist API request failed: HTTP #{res.code} #{res.message}"
          end

          res.body
        end

        # Be tolerant of schema drift — a few shapes seen in the wild:
        #
        #   {"blacklist_keywords": [{"keywords": "a"}, {"keywords": ["b","c"]}]}  (current API)
        #   {"blacklist_keywords": ["a", "b", "c"]}                               (flat)
        #   {"keywords": ["a", "b", "c"]}                                         (flatter)
        #   ["a", "b", "c"]                                                       (bare array)
        def extract_keywords(payload)
          case payload
          when String then [payload]
          when Array  then payload.flat_map { |item| extract_keywords(item) }
          when Hash
            keywords = payload["blacklist_keywords"] || payload["keywords"] || payload["data"]
            keywords ? extract_keywords(keywords) : []
          else []
          end
        end

        def blank?(value)
          value.nil? || value.to_s.strip.empty?
        end

        def redact(uri)
          masked = uri.dup
          if masked.query
            params = URI.decode_www_form(masked.query).map { |k, v| k == "token" ? [k, "***"] : [k, v] }
            masked.query = URI.encode_www_form(params)
          end
          masked.to_s
        end
      end
    end
  end
end
