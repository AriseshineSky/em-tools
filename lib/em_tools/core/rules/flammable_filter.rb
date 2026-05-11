# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Block products with explicit flammable-liquid hazmat signals. # -- ported 1:1 from em-tasks.
      class FlammableFilter < Strategy
        BLOCK_UN_IDS = ["UN1987"].to_set.freeze # ALCOHOLS, N.O.S.
        BLOCK_PRODUCT_TYPES = ["HAND_SANITIZER"].to_set.freeze

        def check(product)
          product = product.is_a?(Hash) ? product : {}
          attributes = product["attributes"] || {}
          hazmat = Array(attributes["hazmat"])

          shipping_name = ""
          un_id = ""
          hazard_class = ""

          hazmat.each do |item|
            next unless item.is_a?(Hash)

            aspect = item["aspect"].to_s.downcase
            value = item["value"].to_s.upcase
            case aspect
            when "proper_shipping_name"
              shipping_name = value
            when "united_nations_regulatory_id"
              un_id = value
            when "transportation_regulatory_class"
              hazard_class = value
            end
          end

          return failed_result("[FlammableHazmat:UN1987]") if BLOCK_UN_IDS.include?(un_id)

          if shipping_name.include?("ALCOHOLS") && hazard_class == "3"
            return failed_result("[FlammableHazmat:AlcoholClass3]")
          end

          flammable_product_type = blocked_product_type(product, hazard_class)
          return failed_result("[FlammableProductType:#{flammable_product_type}]") if flammable_product_type

          passed_result
        end

        private

        def blocked_product_type(product, hazard_class)
          return unless hazard_class == "3"

          Array(product["productTypes"]).each do |item|
            next unless item.is_a?(Hash)

            product_type = item["productType"].to_s.upcase
            return product_type if BLOCK_PRODUCT_TYPES.include?(product_type)
          end
          nil
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    end
  end
end
