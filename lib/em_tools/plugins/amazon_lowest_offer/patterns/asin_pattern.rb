# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonLowestOffer
      module Patterns
        # Shared ASIN detection for lowest-offer seed parsing and +em_inventory+ product id extraction.
        module AsinPattern
          RE = /\A(?:B[0-9A-Z]{9}|[0-9]{9}[0-9X])\z/

          module_function

          def match?(str)
            u = str.to_s.strip.upcase
            return false if u.empty?

            u.match?(RE)
          end
        end
      end
    end
  end
end
