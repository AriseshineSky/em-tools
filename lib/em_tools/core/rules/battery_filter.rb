# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Detect products that include batteries.
      class BatteryFilter < Strategy
        BATTERY_KEYWORDS = [
          'lithium ion batteries',
          'lithium metal batteries',
          'contained in equipment',
          'packed with equipment',
          'un3480',
          'un3481',
          'un3090',
          'un3091'
        ].freeze

        def check(product)
          product = product.is_a?(Hash) ? product : {}
          attributes = product['attributes'] || product[:attributes] || {}

          return failed_result('[IncludeBattery]') if batteries_included?(attributes)
          return failed_result('[IncludeBatteryHazmat]') if hazmat_battery?(attributes)

          passed_result
        end

        private

        def batteries_included?(attributes)
          Array(attributes['batteries_included'] || attributes[:batteries_included]).any? do |flag|
            flag.is_a?(Hash) && (flag['value'] == true || flag[:value] == true)
          end
        end

        def hazmat_battery?(attributes)
          Array(attributes['hazmat'] || attributes[:hazmat]).any? do |item|
            next false unless item.is_a?(Hash)

            value = (item['value'] || item[:value]).to_s.downcase
            BATTERY_KEYWORDS.any? { |keyword| value.include?(keyword) }
          end
        end
      end
    end
  end
end
