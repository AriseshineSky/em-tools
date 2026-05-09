# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Block fresh/perishable food (conservatively, to avoid false positives on packaged groceries).
      class FoodFilter < Strategy
        FRESH_FOOD_PRODUCT_TYPES = Set.new(%w[FRUIT FISH MEAT VEGETABLE SEAFOOD EGG]).freeze

        FRESH_CATEGORY_KEYWORDS = [
          'fresh & chilled',
          'fish & seafood',
          'fruit & vegetables',
          'fresh fruits',
          'fresh meat',
          'dairy, eggs & plant-based alternatives',
          '冷蔵',
          '生鮮'
        ].freeze

        NON_FOOD_PRODUCT_TYPES = Set.new(%w[
                                           ALCOHOLIC_BEVERAGE APPAREL_BELT BATHWATER_ADDITIVE BAKING_CUP BAKING_PAN
                                           BEAUTY CADDY CELLULAR_PHONE_CASE CHOPSTICK COFFEE_FILTER COFFEE_MAKER
                                           COOKING_CONTAINER COOKING_POT CONDOM CONTACT_LENSES COSTUME_HEADWEAR
                                           DISHWARE_BOWL DRINKING_CUP DRINK_COASTER DRINK_FLAVORED DYE
                                           EDIBLE_OIL_VEGETABLE ELECTRONIC_CABLE FERTILIZER FISHING_LINE FISHING_REEL
                                           FLATWARE FOOD_STRAINER FOOD_STORAGE_CONTAINER GLUCOSE_METER GROCERY
                                           HAIR_TIE HEALTH_PERSONAL_CARE HOME HONEY JUICE_AND_JUICE_DRINK KEYCAP
                                           KITCHEN_TOOLS LAUNDRY_DETERGENT LEASH LEGUME LIGHT_BULB MARKING_PEN
                                           MEDICATION MEAL_HOLDER MINERAL_SUPPLEMENT NUTRITIONAL_SUPPLEMENT
                                           PACKAGED_SOUP_AND_STEW PASTRY PERSONAL_FRAGRANCE PET_FOOD PIERCING_JEWELRY
                                           PITCHER PRESSURE_COOKER PROTEIN_SUPPLEMENT_POWDER ROTATING_TRAY SAFETY_MASK
                                           SAUCE SEASONING SEASONING_MILL SHOES SIGNAGE SKIN_CLEANING_AGENT
                                           SNACK_CHIP_AND_CRISP SNACK_FOOD_BAR SPOON SPORTING_GOODS STORAGE_HOOK
                                           STRINGED_INSTRUMENTS SUGAR_CANDY TEA TEA_INFUSER TOOLS TOOTH_WHITENER
                                           TOYS_AND_GAMES URN VEHICLE_BAG VINEGAR VITAMIN WRITING_PAPER
                                         ]).freeze

        def check(product)
          return passed_result unless product.is_a?(Hash)

          product_types = extract_product_types(product)
          return passed_result if intersect_upcase?(product_types, NON_FOOD_PRODUCT_TYPES)
          return passed_result unless intersect_upcase?(product_types, FRESH_FOOD_PRODUCT_TYPES)

          context_text = [
            extract_category_texts(product).join(' '),
            extract_classification_texts(product).join(' ')
          ].join(' ')
          return failed_result('freshfood') if contains_keyword?(context_text, FRESH_CATEGORY_KEYWORDS)

          passed_result
        end

        private

        def intersect_upcase?(values, allowed_set)
          values.any? { |v| v && allowed_set.include?(v.to_s.upcase) }
        end

        def contains_keyword?(text, keywords)
          haystack = text.to_s.downcase
          keywords.any? { |keyword| haystack.include?(keyword) }
        end

        def extract_product_types(product)
          Array(product['productTypes']).filter_map do |item|
            next unless item.is_a?(Hash)

            item['productType']&.to_s
          end
        end

        def extract_category_texts(product)
          Array(product['categories']).filter_map do |item|
            next unless item.is_a?(Hash)

            item['cat_name']&.to_s&.downcase
          end
        end

        def extract_classification_texts(product)
          values = []
          Array(product['classifications']).each do |root|
            next unless root.is_a?(Hash)

            Array(root['classifications']).each do |cls|
              collect_classification_chain(cls, values)
            end
          end
          values
        end

        def collect_classification_chain(node, values)
          current = node
          while current.is_a?(Hash) && !current.empty?
            display_name = current['displayName']
            values << display_name.to_s.downcase if display_name
            current = current['parent']
          end
        end
      end
    end
  end
end
