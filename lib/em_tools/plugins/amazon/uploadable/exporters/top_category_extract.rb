# frozen_string_literal: true

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Exporters
          # Resolves first-level category labels from +amz_products_api_*_v2+ documents.
          module TopCategoryExtract
            UNCATEGORIZED = "Uncategorized"

            module_function

            def resolve(source, category_from: :top_category)
              return UNCATEGORIZED unless source.is_a?(Hash)

              if category_from == :categories_first
                first_category_name(source) || top_category_name(source) || UNCATEGORIZED
              else
                top_category_name(source) || first_category_name(source) || UNCATEGORIZED
              end
            end

            def top_category_name(source)
              v = source["top_category"] || source[:top_category]
              s = v.to_s.strip
              s.empty? ? nil : s
            end

            def first_category_name(source)
              cats = source["categories"] || source[:categories]
              return unless cats.is_a?(Array) && cats.first.is_a?(Hash)

              c = cats.first
              name = c["cat_name"] || c[:cat_name]
              s = name.to_s.strip
              s.empty? ? nil : s
            end
          end
        end
      end
    end
  end
end
