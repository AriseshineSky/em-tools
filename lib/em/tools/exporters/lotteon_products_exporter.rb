# frozen_string_literal: true

module Em
  module Tools
    module Exporters
      class LotteonProductsExporter
        EXPORTER_KEY = 'lotteon_products'

        def initialize(client = nil)
          @client = client || Em::Clients::ElasticsearchClient.new(
            url: Em::Tools::Config.exporter_elasticsearch_url(EXPORTER_KEY)
          )
          @index = Em::Tools::Config.exporter_index(EXPORTER_KEY, 'user1_lotteon_products')
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
