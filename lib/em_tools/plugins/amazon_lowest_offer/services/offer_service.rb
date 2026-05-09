# frozen_string_literal: true

require 'json'
require 'time'

module EmTools
  module Plugins
    module AmazonLowestOffer
      module Services
        # Ruby port of +em_tasks/utils/offer_services.py::AmzOfferService+, restricted to the
        # +get_offers(marketplace, asins, condition)+ slice consumed by the ported Amazon
        # uploadable formatter / loader chain.
        #
        # Mirrors the Python composition in {AmzOfferService.__init__}:
        # +EsLowestOfferListingOfferService+ (ES batch fetch) +
        # +EsLowestOfferListingOfferConverter+ (parses +_source.offers+ JSON) +
        # +LowestOfferListingOfferFilter+ (seller-side rules) +
        # +OfferServiceLowestOfferListingPriceFinder+ (composes the above + sort/pick).
        #
        # Index docs in +lowest_offer_listings_<mp>_<condition>+ have shape:
        #   { _id: ASIN, _source: { asin:, time:, offers: "<JSON-encoded array of offer hashes>" } }
        # Each offer in that array carries seller fields (+fba+, +rating+, +feedback+,
        # +shipping_time+, +subcondition+, +ships_from+, +country+, +price+, +product_price+,
        # +shipping_price+, +currency+, ...) which {Filters::OfferFilter} evaluates.
        #
        # +get_lowest_offer+ and +analyze_offers+ from the Python class are intentionally not
        # ported: no caller in this gem references them today.
        # rubocop:disable Metrics/ClassLength -- mirrors Python composition surface
        class OfferService
          DEFAULT_CONDITION = 'new'
          DEFAULT_MAX_RETRIES = 3
          DEFAULT_TRANSIENT_DELAY_SECONDS = 10
          DEFAULT_EXCEPTION_DELAY_SECONDS = 3

          attr_reader :marketplace, :condition, :offer_index, :filter

          # @param client [#mget, #index_exists?] Elasticsearch client (e.g. +EmTools::Clients::ElasticsearchClient+).
          # @param marketplace [String] +us+, +fr+, ... (lower-cased internally).
          # @param condition [String] +new+ / +used+ / etc; appended to default index name.
          # @param filter [Filters::OfferFilter, nil] seller-side filter; defaults to a permissive
          #   filter with +provider_type='min'+ (matches Python's
          #   +AmzOfferService.__init__+ which forces +provider_type='min'+).
          # @param offer_index [String, nil] override; defaults to
          #   +lowest_offer_listings_<marketplace>_<condition>+.
          # @param max_retries [Integer]
          # @param transient_delay [Numeric] sleep when ES response is not a Hash.
          # @param exception_delay [Numeric] sleep when ES raises before returning.
          # @param logger [Logger, nil]
          # @param sleeper [#call] override for tests.
          # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists -- mirrors the Python constructor surface
          def initialize(client:, marketplace:, condition: DEFAULT_CONDITION, filter: nil,
                         offer_index: nil, max_retries: DEFAULT_MAX_RETRIES,
                         transient_delay: DEFAULT_TRANSIENT_DELAY_SECONDS,
                         exception_delay: DEFAULT_EXCEPTION_DELAY_SECONDS,
                         logger: nil, sleeper: nil)
            @client = client
            @marketplace = marketplace.to_s.downcase.strip
            raise ArgumentError, 'marketplace is required' if @marketplace.empty?

            @condition = condition.to_s.downcase.strip
            @condition = DEFAULT_CONDITION if @condition.empty?

            override = offer_index.to_s.strip
            @offer_index = override.empty? ? "lowest_offer_listings_#{@marketplace}_#{@condition}" : override

            @filter = filter || Filters::OfferFilter.new(provider_type: 'min')
            @max_retries = [max_retries.to_i, 0].max
            @transient_delay = transient_delay
            @exception_delay = exception_delay
            @logger = logger || EmTools::Core::Logger.for(progname: 'amz-offer-service')
            @sleeper = sleeper || ->(seconds) { sleep(seconds) }
          end
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists

          # Returns +{ asin => filtered_offer_hash | nil }+ for each requested ASIN. ASINs without a
          # passing offer are present in the result with a +nil+ value (matching Python's
          # +offers.setdefault(asin, False)+, where Ruby +nil+ replaces Python +False+). Returns
          # +{}+ when +asins+ is empty or the index does not exist.
          def get_offers(asins)
            ids = normalize_ids(asins)
            return {} if ids.empty?
            return {} unless index_available?

            resp = fetch_with_retries(ids)
            return {} unless resp.is_a?(Hash)

            converted = convert(resp)
            select_offers(converted, ids)
          end

          private

          def normalize_ids(asins)
            Array(asins).map { |a| a.to_s.strip.upcase }.reject(&:empty?).uniq
          end

          def index_available?
            return true unless @client.respond_to?(:index_exists?)

            @client.index_exists?(@offer_index)
          end

          # rubocop:disable Metrics/MethodLength -- one-shot retry loop mirroring Python's `while max_retries > 0`
          def fetch_with_retries(ids)
            remaining = @max_retries
            loop do
              begin
                resp = @client.mget(index: @offer_index, ids: ids)
              rescue StandardError => e
                @logger.error("[OfferService] #{e.class}: #{e.message}")
                remaining -= 1
                return nil if remaining <= 0

                @sleeper.call(@exception_delay)
                next
              end

              return resp if resp.is_a?(Hash)

              @logger.info('[OfferService] Temporary unavailable! Wait to retry.')
              remaining -= 1
              return nil if remaining <= 0

              @sleeper.call(@transient_delay)
            end
          end
          # rubocop:enable Metrics/MethodLength

          # Mirrors +EsLowestOfferListingOfferConverter.convert+: returns
          # +{ asin => { 'asin' => ..., 'offers' => [Hash, ...], 'time' => '...' } }+.
          # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- string-or-symbol key tolerance mirrors Python dict access
          def convert(resp)
            docs = resp['docs'] || resp[:docs] || []
            out = {}
            docs.each do |doc|
              next unless doc.is_a?(Hash)
              next unless doc['found'] || doc[:found]

              asin = (doc['_id'] || doc[:_id]).to_s.strip.upcase
              next if asin.empty?

              src = doc['_source'] || doc[:_source] || {}
              out[asin] = {
                'asin' => src['asin'] || src[:asin] || asin,
                'offers' => parse_offers(src['offers'] || src[:offers]),
                'time' => src['time'] || src[:time]
              }
            end
            out
          end
          # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

          def parse_offers(raw)
            case raw
            when nil then []
            when Array then raw.select { |o| o.is_a?(Hash) }
            when String
              parsed = safe_json_parse(raw)
              parsed.is_a?(Array) ? parsed.select { |o| o.is_a?(Hash) } : []
            else []
            end
          end

          def safe_json_parse(raw)
            JSON.parse(raw)
          rescue JSON::ParserError
            []
          end

          def select_offers(converted, asins)
            expire_hour = @filter.respond_to?(:expire_hour) ? @filter.expire_hour : nil
            asins.each_with_object({}) do |asin, out|
              entry = converted[asin]
              out[asin] = pick_offer(entry, expire_hour)
            end
          end

          def pick_offer(entry, expire_hour)
            return nil unless entry

            offers = entry['offers']
            return nil if !offers.is_a?(Array) || offers.empty?

            offer = @filter.filter(offers)
            return nil unless offer

            offer['time'] = entry['time']
            offer['expired'] = expired?(entry['time'], expire_hour)
            offer
          end

          def expired?(offer_time, expire_hour)
            return false if expire_hour.nil? || offer_time.nil?

            parsed = offer_time.is_a?(::Time) ? offer_time : ::Time.parse(offer_time.to_s)
            parsed < (::Time.now.utc - (expire_hour.to_i * 3600))
          rescue ArgumentError
            false
          end
        end
        # rubocop:enable Metrics/ClassLength
      end
    end
  end
end
