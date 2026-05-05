# frozen_string_literal: true

module Em
  module Tools
    module Scanners
      class SsgProductsScanner
        def initialize(_client)
          @client = cline
        end

        def each(&block)
          @client.iterate_all(index: 'ssg_products', &block)
        end
      end
    end
  end
end
