# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonLowestOffer
      module Sources
        # Loads distinct Amazon ASINs (+source_product_id+) from the +em_inventory+ Elasticsearch index
        # for use with {LowestOfferListingsCoverageQuery} (+LOWEST_OFFER_ID_SOURCE=inventory+).
        #
        # Expected +_source+ fields (names configurable via ENV, see +initialize+):
        # - +source+ (or +source.keyword+ for queries): must match one of the configured Amazon source tokens.
        # - +source_product_id+: ASIN-like string for +terms+ queries against +lowest_offer_listings_<mp>_new+.
        #
        # Optional +marketplace_field+ narrows inventory rows to the current marketplace code (+mp+ is +de+, +us+, …).
        class InventoryAsinLoader # -- ES field names are explicit for operability
          def initialize(es_client:, index:, source_field:, source_terms:, product_id_field:,
            marketplace_field: nil, max_hits: nil)
            @es_client = es_client
            @index = index.to_s.strip
            @source_field = source_field.to_s.strip
            @source_terms = normalize_source_terms(source_terms)
            @product_id_field = product_id_field.to_s.strip
            @marketplace_field = marketplace_field.to_s.strip
            @marketplace_field = nil if @marketplace_field.empty?
            @max_hits = resolve_max_hits(max_hits)
          end

          # Returns sorted unique ASIN strings (same shape as seed-derived IDs for +LowestOfferListingsCoverageQuery+).
          def load(mkt)
            return [] if @index.empty? || @source_terms.empty? || @product_id_field.empty?
            return [] unless @es_client.index_exists?(@index)

            seen = Set.new
            yielded = 0
            @es_client.iterate_query(
              index: @index,
              query: build_query(mkt),
              batch_size: 2_000,
              max_hits: @max_hits,
            ) do |hit|
              yielded += 1
              raw = extract_product_id(hit)
              next if raw.nil?

              sid = raw.to_s.strip.upcase
              next unless EmTools::Plugins::AmazonLowestOffer::Patterns::AsinPattern.match?(sid)

              seen << sid
            end

            warn_max_hits if @max_hits && yielded >= @max_hits

            seen.to_a.sort
          end
          # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

          private

          def resolve_max_hits(max_hits)
            raw_max = max_hits
            raw_max = ENV["LOWEST_OFFER_INVENTORY_MAX_HITS"].to_s.strip if raw_max.nil?
            mh = raw_max.to_s.empty? ? nil : Integer(raw_max, exception: false)
            mh&.positive? ? mh : nil
          end

          def warn_max_hits
            warn("InventoryAsinLoader: hit LOWEST_OFFER_INVENTORY_MAX_HITS limit; " \
              "distinct ASIN count may be incomplete. Increase limit or narrow inventory query.")
          end

          def normalize_source_terms(list)
            arr = Array(list).flat_map { |s| s.to_s.split(",") }.map(&:strip).reject(&:empty?)
            return ["amazon", "amz"] if arr.empty?

            arr.uniq
          end

          def build_query(mkt)
            filters = [
              { terms: { @source_field => @source_terms } },
            ]
            filters << { term: { @marketplace_field => inventory_marketplace_value(mkt) } } if @marketplace_field
            { bool: { filter: filters } }
          end

          # Default: lowercase +mkt+ (+de+, +us+) to match common keyword values.
          def inventory_marketplace_value(mkt)
            if ENV.fetch("LOWEST_OFFER_INVENTORY_MARKETPLACE_VALUE_MODE", "downcase") == "upcase"
              mkt.to_s.upcase
            else
              mkt.to_s.downcase
            end
          end

          def extract_product_id(hit)
            src = hit["_source"] || {}
            key = @product_id_field
            return src[key] if src.key?(key)
            return src[key.to_sym] if src.key?(key.to_sym)

            nil
          end
        end
      end
    end
  end
end
