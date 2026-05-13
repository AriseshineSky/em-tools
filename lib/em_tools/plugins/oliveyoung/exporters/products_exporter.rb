# frozen_string_literal: true

require "json"

module EmTools
  module Plugins
    module Oliveyoung
      module Exporters
        # Streams Oliveyoung products out of Elasticsearch as NDJSON.
        #
        # The shape of "what is an Oliveyoung product" lives in
        # {EmTools::Plugins::Oliveyoung::Queries::ProductsQuery} — this class
        # only owns transport (PIT scan + NDJSON serialisation). To change the
        # filter, swap the +query:+ injected by the plugin factory; do **not**
        # add domain logic here.
        class ProductsExporter
          EXPORTER_KEY = "oliveyoung_products"

          # @param client [EmTools::Clients::ElasticsearchClient, nil] optional;
          #   defaults from {EmTools::Core::Config}.
          # @param query [Hash, #to_h] ES query value (no +query:+ envelope).
          #   Defaults to {Queries::ProductsQuery} with stock settings.
          # @param index [String, nil] override the index name.
          def initialize(client: nil, query: nil, index: nil)
            @client = client || EmTools::Clients::ElasticsearchClient.new(
              url: EmTools::Core::Config.exporter_elasticsearch_url(EXPORTER_KEY),
            )
            @index = index || EmTools::Core::Config.exporter_index(EXPORTER_KEY, "oliveyoung_products")
            @query = (query || Queries::ProductsQuery.new).then { |q| q.respond_to?(:to_h) ? q.to_h : q }
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
            @client.iterate_query(index: @index, query: @query, batch_size: batch_size, &block)
          end
        end
      end
    end
  end
end
