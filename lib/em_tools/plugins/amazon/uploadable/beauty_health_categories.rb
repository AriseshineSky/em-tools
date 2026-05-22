# frozen_string_literal: true

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        # First-level +top_category+ labels for Beauty + Health & Personal Care per marketplace.
        module BeautyHealthCategories
          BY_MARKETPLACE = {
            "de" => ["Beauty", "Health & Personal Care"],
            "uk" => ["Beauty", "Health & Personal Care"],
            "jp" => ["Beauty", "Health & Personal Care"],
            "in" => ["Beauty", "Health & Personal Care"],
            "ca" => ["Beauty & Personal Care", "Health & Personal Care"],
            "mx" => ["Belleza", "Salud y Cuidado Personal"],
            "ae" => ["Beauty", "Health"],
            "fr" => ["Beauté et Parfum", "Hygiène et Santé"],
            "it" => ["Bellezza", "Salute e cura della persona"],
          }.freeze

          def self.for_marketplace(marketplace)
            mp = marketplace.to_s.strip.downcase
            list = BY_MARKETPLACE[mp]
            return list.dup if list

            raise EmTools::Core::Errors::ConfigurationError,
              "no Beauty/Health category mapping for marketplace #{mp.inspect}; " \
                "use -c explicitly or add to BeautyHealthCategories::BY_MARKETPLACE"
          end
        end
      end
    end
  end
end
