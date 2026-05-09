# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Broader fresh-food / grocery detection across product types, summaries, sales ranks, title and description.
      class FreshFoodFilter < Strategy
        FOOD_KEYWORDS = Set.new(%w[
                                  food grocery beverage drink
                                  frozen fresh meat fish seafood
                                  eel shrimp crab salmon
                                  ingredients sauce snack
                                ]).freeze

        FOOD_PRODUCT_TYPES = Set.new(%w[
                                       FOOD GROCERY SHELLFISH MEAT SEAFOOD PRODUCE
                                     ]).freeze

        def check(product)
          product = product.is_a?(Hash) ? product : {}

          return failed_result('[FresFood]') if matching_product_type?(product)
          return failed_result('[FresFood]') if matching_summary_group?(product)
          return failed_result('[FresFood]') if matching_sales_rank?(product)
          return failed_result('[FresFood]') if matching_title?(product)
          return failed_result('[FresFood]') if matching_description?(product)

          passed_result
        end

        private

        def matching_product_type?(product)
          Array(product['productTypes']).any? do |item|
            item.is_a?(Hash) && FOOD_PRODUCT_TYPES.include?(item['productType'])
          end
        end

        def matching_summary_group?(product)
          Array(product['summaries']).any? do |summary|
            next false unless summary.is_a?(Hash)

            group = summary['websiteDisplayGroupName'].to_s.downcase
            group.include?('grocery') || group.include?('food')
          end
        end

        def matching_sales_rank?(product)
          Array(product['sales_ranks']).any? do |rank|
            next false unless rank.is_a?(Hash)

            cat = rank['category'].to_s.downcase
            FOOD_KEYWORDS.any? { |k| cat.include?(k) }
          end
        end

        def matching_title?(product)
          title = product['title'].to_s.downcase
          FOOD_KEYWORDS.any? { |k| title.include?(k) }
        end

        def matching_description?(product)
          Array(product.dig('attributes', 'product_description')).any? do |desc|
            next false unless desc.is_a?(Hash)

            text = desc['value'].to_s.downcase
            text.include?('ingredient') || text.include?('keep frozen')
          end
        end
      end
    end
  end
end
