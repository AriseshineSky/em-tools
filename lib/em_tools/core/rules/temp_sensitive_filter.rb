# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Temperature-sensitive product detection (title-only).
      class TempSensitiveFilter < Strategy
        TITLE_KEYWORDS = Set.new([
                                   'frozen', 'freeze', 'chilled', 'refrigerated',
                                   'keep frozen', 'keep refrigerated',
                                   '冷凍', '冷蔵', '要冷凍', '要冷蔵', 'クール便', 'チルド', '保冷',
                                   '要冷藏', '需冷藏', '需冷冻'
                                 ]).freeze

        def check(product)
          title = (product.is_a?(Hash) ? product['title'] : nil).to_s.downcase

          if (keyword = TITLE_KEYWORDS.find { |k| title.include?(k.downcase) })
            return failed_result("[TempSensitiveTitle:#{keyword}]")
          end

          passed_result
        end
      end
    end
  end
end
