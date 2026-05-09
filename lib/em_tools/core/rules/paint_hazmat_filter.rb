# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Detect paint-like products with explicit hazmat shipping signals (UN1263, Class 3, NAIL_POLISH).
      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- ported 1:1 from em-tasks.
      class PaintHazmatFilter < Strategy
        def check(product)
          product = product.is_a?(Hash) ? product : {}
          attributes = product['attributes'] || {}
          hazmat = Array(attributes['hazmat'])
          product_types = Array(product['productTypes'])

          shipping_names = []
          un_ids = []
          hazard_classes = []

          hazmat.each do |item|
            next unless item.is_a?(Hash)

            aspect = item['aspect'].to_s.downcase
            value = item['value'].to_s.upcase
            case aspect
            when 'proper_shipping_name' then shipping_names << value
            when 'united_nations_regulatory_id' then un_ids << value
            when 'transportation_regulatory_class' then hazard_classes << value
            end
          end

          has_paint_shipping_name = shipping_names.any? { |name| name.include?('PAINT') }
          has_un1263 = un_ids.include?('UN1263')
          has_class3 = hazard_classes.include?('3')

          return failed_result('[HazmatPaint]') if has_paint_shipping_name && (has_un1263 || has_class3)

          return failed_result('[HazmatPaint:NailPolish]') if (has_un1263 || has_class3) && nail_polish?(product_types)

          passed_result
        end

        private

        def nail_polish?(product_types)
          product_types.any? do |item|
            item.is_a?(Hash) && item['productType'].to_s.upcase == 'NAIL_POLISH'
          end
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    end
  end
end
