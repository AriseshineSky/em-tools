# frozen_string_literal: true

module Em
  module Tools
    module Scanners
      class SsgProductsScanner
        EXPORTER_KEY = 'ssg_products'

        def initialize(client = nil)
          @client = client || Em::Clients::ElasticsearchClient.new(
            url: Em::Tools::Config.exporter_elasticsearch_url(EXPORTER_KEY)
          )
          @index = Em::Tools::Config.exporter_index(EXPORTER_KEY, 'ssg_products')
        end

        def each(&block)
          @client.iterate_all(index: @index, &block)
        end
      end
    end
  end
end
