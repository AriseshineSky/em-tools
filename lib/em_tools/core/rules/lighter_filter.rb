# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Detect lighter products that should be filtered out.
      class LighterFilter < Strategy
        BLOCKED_PRODUCT_TYPES = Set.new(["MECHANICAL_LIGHTER", "LIGHTER", "CIGARETTE_LIGHTER"]).freeze
        TITLE_KEYWORDS = ["lighter", "turbo flame", "jet flame"].freeze
        HAZMAT_KEYWORDS = ["lighter", "lighters"].freeze

        def check(product)
          product = product.is_a?(Hash) ? product : {}

          if (blocked = blocked_product_type(product))
            return failed_result("[LighterProductType:#{blocked}]")
          end

          title = product["title"].to_s.downcase
          if (keyword = TITLE_KEYWORDS.find { |k| title.include?(k) })
            return failed_result("[LighterKeyword:#{keyword}]")
          end

          return failed_result("[LighterHazmat]") if hazmat_lighter?(product)

          passed_result
        end

        private

        def blocked_product_type(product)
          Array(product["productTypes"]).each do |item|
            next unless item.is_a?(Hash)

            product_type = item["productType"].to_s.upcase
            return product_type if BLOCKED_PRODUCT_TYPES.include?(product_type)
          end
          nil
        end

        def hazmat_lighter?(product)
          Array(product.dig("attributes", "hazmat")).any? do |item|
            next false unless item.is_a?(Hash)

            value = item["value"].to_s.downcase
            HAZMAT_KEYWORDS.any? { |k| value.include?(k) }
          end
        end
      end
    end
  end
end
