# frozen_string_literal: true

module EmTools
  module Plugins
    module Oliveyoung
      module Scanners
        class ProductsScanner
          def initialize(client, context)
            @client = client
            @index = EmTools::Core::Config.exporter_index(EXPORTER_KEY, "ssg_products")
          end

          def each(&block)
            @client.iterate_all(index: @index, &block)
          end
        end
      end
    end
  end
end
