# frozen_string_literal: true

module EmTools
  module Plugins
    module Ssg
      module Scanners
        class ProductsScanner
          EXPORTER_KEY = 'ssg_products'

          def initialize(client = nil)
            @client = client || EmTools::Clients::ElasticsearchClient.new(
              url: EmTools::Core::Config.exporter_elasticsearch_url(EXPORTER_KEY)
            )
            @index = EmTools::Core::Config.exporter_index(EXPORTER_KEY, 'ssg_products')
          end

          def each(&block)
            @client.iterate_all(index: @index, &block)
          end
        end
      end
    end
  end
end
