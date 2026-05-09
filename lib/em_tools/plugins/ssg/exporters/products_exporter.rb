# frozen_string_literal: true

module EmTools
  module Plugins
    module Ssg
      module Exporters
        class ProductsExporter
          EXPORTER_KEY = 'ssg_products'

          # @param client [EmTools::Clients::ElasticsearchClient, nil] optional; default from Config.
          def initialize(client = nil)
            @client = client || EmTools::Clients::ElasticsearchClient.new(
              url: EmTools::Core::Config.exporter_elasticsearch_url(EXPORTER_KEY)
            )
            @index = EmTools::Core::Config.exporter_index(EXPORTER_KEY, 'ssg_products')
          end

          def to_jsonl(file_path)
            File.open(file_path, 'w') do |f|
              each do |doc|
                f.puts(doc['_source'].to_json)
              end
            end
          end

          def each(&block)
            @client.iterate_all(index: @index, &block)
          end
        end
      end
    end
  end
end
