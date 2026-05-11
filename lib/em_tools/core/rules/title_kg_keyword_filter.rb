# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Block products whose title implies large unit weight, e.g. +"5 kg"+ ... +"10 kg"+.
      class TitleKgKeywordFilter < Strategy
        KG_PATTERN = /(10|[1-9])\s*kg\b/i

        def check(product)
          title = (product.is_a?(Hash) ? product["title"] : nil).to_s
          match = title.match(KG_PATTERN)
          return passed_result unless match

          failed_result("[TitleWeightKeyword:#{match[1]}kg]")
        end
      end
    end
  end
end
