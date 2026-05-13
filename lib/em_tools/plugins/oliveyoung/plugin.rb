# frozen_string_literal: true

module EmTools
  module Plugins
    module Oliveyoung
      # Korean marketplace - Oliveyoung. Bundles the products NDJSON exporter
      # (filtered to +source=oliveyoung+ via
      # {Queries::ProductsQuery}) and the keyword scanner.
      class Plugin < EmTools::Core::Plugin::Base
        EmTools::Core::PluginRegistry.register(:oliveyoung, self)

        def capabilities
          {
            products: {
              exporter: Exporters::ProductsExporter,
              query: Queries::ProductsQuery,
              scanner: Scanners::ProductsScanner,
            },
          }
        end

        def dependencies
          @dependencies ||= {
            es_client: EmTools::Clients::ElasticsearchClient.new(
              url: EmTools::Core::Config.exporter_elasticsearch_url(Exporters::ProductsExporter::EXPORTER_KEY),
            ),
          }
        end

        def cli_commands
          {
            "products export" => Cli::ExportProducts,
          }
        end

        # Factory: returns a configured exporter. The +source+ filter is
        # already wired in via the default query; pass +source_value:+ to
        # override for ad-hoc one-offs without forking the class.
        def products_exporter(client: dependencies[:es_client], source_value: nil, **_opts)
          query = source_value ? Queries::ProductsQuery.new(source_value: source_value) : nil
          capabilities.dig(:products, :exporter).new(client: client, query: query)
        end

        def products_scanner(**opts)
          capabilities.dig(:products, :scanner).new(**opts)
        end
      end
    end
  end
end
