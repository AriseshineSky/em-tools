# frozen_string_literal: true

require "json"

module EmTools
  module Plugins
    module Lotteon
      module Exporters
        class ProductsExporter
          EXPORTER_KEY = "lotteon_products"

          def initialize(client: nil)
            @client = client || EmTools::Clients::ElasticsearchClient.new(
              url: EmTools::Core::Config.exporter_elasticsearch_url(EXPORTER_KEY),
            )
            @index = EmTools::Core::Config.exporter_index(EXPORTER_KEY, "user1_lotteon_products")
          end

          def to_jsonl(file_path, batch_size: 1000)
            File.open(file_path, "w") do |f|
              write_jsonl(f, batch_size: batch_size)
            end
          end

          def write_jsonl(io, batch_size: 1000)
            each(batch_size: batch_size) do |doc|
              io.puts(doc["_source"].to_json)
            end
          end

          def each(batch_size: 1000, &block)
            @client.iterate_all(index: @index, batch_size: batch_size, &block)
          end
        end
      end
    end
  end
end
