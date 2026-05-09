# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Detect industrial paints / coatings while letting cosmetic ("hair dye", "balayage") products pass.
      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- ported 1:1 from em-tasks.
      class PaintFilter < Strategy
        PAINT_KEYWORDS = [
          'automotive paint', 'body paint', 'touch-up paint', 'spray paint',
          'primer', 'lacquer', 'enamel', 'coating'
        ].freeze

        GENERIC_PAINT_WORD = 'paint'

        SAFE_BEAUTY_KEYWORDS = [
          'hair', 'dye', 'balayage', 'ombre', 'toner',
          'hair painting', 'hair dye brush', 'hair coloring'
        ].freeze

        DANGEROUS_CONTEXT_KEYWORDS = [
          'automotive', 'car', 'vehicle',
          'metal', 'wood', 'wall',
          'industrial', 'furniture',
          'touch up', 'refinish'
        ].freeze

        PAINT_CATEGORIES = ['PAINTS & PRIMERS', 'BODY PAINT', 'AUTOMOTIVE BODY PAINT'].freeze
        PAINT_PRODUCT_TYPES = %w[PAINT].freeze

        def check(product)
          restricted_paint?(product) ? failed_result('[RestrictedPaint]') : passed_result
        end

        def restricted_paint?(product)
          product = normalize_product(product)
          text = collect_text(product)
          categories = categories_upcase(product)
          product_types = product_types_upcase(product)

          return false if categories.any? { |c| c.include?('BEAUTY') || c.include?('HAIR') }
          return false if product_types.any? { |pt| pt.include?('BEAUTY') }
          return false if SAFE_BEAUTY_KEYWORDS.any? { |kw| text.include?(kw) }

          return true if PAINT_KEYWORDS.any? { |kw| text.match?(/\b#{Regexp.escape(kw)}\b/) }

          if text.match?(/\b#{GENERIC_PAINT_WORD}\b/) &&
             DANGEROUS_CONTEXT_KEYWORDS.any? { |ctx| text.include?(ctx) }
            return true
          end

          return true if categories.any? { |c| PAINT_CATEGORIES.include?(c) }
          return true if product_types.any? { |pt| PAINT_PRODUCT_TYPES.include?(pt) }

          false
        end

        private

        def normalize_product(product)
          return {} unless product.is_a?(Hash)

          dup = product.dup
          dup['categories'] ||= []
          dup['productTypes'] ||= []
          attrs = (dup['attributes'] || {}).dup
          attrs['bullet_point'] ||= []
          attrs['product_description'] ||= []
          dup['attributes'] = attrs
          dup
        end

        def collect_text(product)
          title = product['title'].to_s
          bullets = Array(product.dig('attributes', 'bullet_point')).filter_map do |bp|
            bp.is_a?(Hash) ? bp['value'] : nil
          end.join(' ')
          descriptions = Array(product.dig('attributes', 'product_description')).filter_map do |desc|
            desc.is_a?(Hash) ? desc['value'] : nil
          end.join(' ')
          "#{title} #{bullets} #{descriptions}".downcase
        end

        def categories_upcase(product)
          Array(product['categories']).filter_map do |c|
            next unless c.is_a?(Hash)

            c['cat_name'].to_s.upcase
          end
        end

        def product_types_upcase(product)
          Array(product['productTypes']).filter_map do |pt|
            next unless pt.is_a?(Hash)

            pt['productType'].to_s.upcase
          end
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    end
  end
end
