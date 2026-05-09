# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Block foaming/aerosol products that double as hazmat (aerosol/spray/mousse + Class 2/2.1/3 hazmat).
      class FoamFilter < Strategy
        FOAM_KEYWORDS = %w[foam foaming フォーム].freeze

        FOAM_HAZMAT_CONTEXT_KEYWORDS = %w[
          aerosol spray mist mousse carbonated
        ].to_set.merge(%w[炭酸 スプレー ムース]).freeze

        def check(product)
          product = product.is_a?(Hash) ? product : {}
          text = collect_text(product)

          FOAM_KEYWORDS.each do |keyword|
            return failed_result("[HazmatKeyword:#{keyword}]") if hazmat_foam?(product, text, keyword)
          end

          passed_result
        end

        # Public for use from {HazmatFilter}.
        def hazmat_class(product)
          attrs = product['attributes'] || {}
          Array(attrs['hazmat']).each do |item|
            next unless item.is_a?(Hash)

            return item['value'].to_s if item['aspect'] == 'transportation_regulatory_class'
          end
          nil
        end

        private

        def hazmat_foam?(product, text, keyword)
          return false unless text.include?(keyword.downcase)
          return true if FOAM_HAZMAT_CONTEXT_KEYWORDS.any? { |ctx| text.include?(ctx) }

          %w[2 2.1 3].include?(hazmat_class(product))
        end

        def collect_text(product)
          title = product['title'].to_s
          bullets = Array(product.dig('attributes', 'bullet_point')).filter_map do |bp|
            bp.is_a?(Hash) ? bp['value'] : nil
          end.join(' ')
          "#{title} #{bullets}".downcase
        end
      end
    end
  end
end
