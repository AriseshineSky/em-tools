# frozen_string_literal: true

module EmTools
  module Plugins
    module Ebay
      module Sources
        # Pulls product ids from an inventory ES index for {EmTools::Plugins::Ebay::Queries::ListingsCoverageQuery}
        # when +EBAY_LISTINGS_COVERAGE_ID_SOURCE=inventory+.
        #
        # Unlike {EmTools::Plugins::Amazon::LowestOffer::Sources::InventoryAsinLoader}, ids are **not**
        # validated as ASINs (numeric eBay item ids are expected).
        class InventoryProductIdLoader
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

              sid = raw.to_s.strip
              next if sid.empty?

              seen << sid
            end

            warn_max_hits if @max_hits && yielded >= @max_hits

            seen.to_a.sort
          end
          # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

          private

          def resolve_max_hits(max_hits)
            raw_max = max_hits
            raw_max = ENV["EBAY_LISTINGS_COVERAGE_INVENTORY_MAX_HITS"].to_s.strip if raw_max.nil?
            mh = raw_max.to_s.empty? ? nil : Integer(raw_max, exception: false)
            mh&.positive? ? mh : nil
          end

          def warn_max_hits
            warn("InventoryProductIdLoader: hit EBAY_LISTINGS_COVERAGE_INVENTORY_MAX_HITS limit; " \
              "distinct product id count may be incomplete.")
          end

          def normalize_source_terms(list)
            arr = Array(list).flat_map { |s| s.to_s.split(",") }.map(&:strip).reject(&:empty?)
            return ["Ebay_US"] if arr.empty?

            arr.uniq
          end

          def build_query(mkt)
            filters = [
              { terms: { @source_field => @source_terms } },
            ]
            filters << { term: { @marketplace_field => inventory_marketplace_value(mkt) } } if @marketplace_field
            { bool: { filter: filters } }
          end

          def inventory_marketplace_value(mkt)
            if ENV.fetch("EBAY_LISTINGS_COVERAGE_INVENTORY_MARKETPLACE_VALUE_MODE", "downcase") == "upcase"
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
