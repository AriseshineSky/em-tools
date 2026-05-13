# frozen_string_literal: true

module EmTools
  module Plugins
    module Ssg
      # Korean marketplace - SSG. Bundles the products NDJSON exporter and the keyword scanner.
      class Plugin < EmTools::Core::Plugin::Base
        EmTools::Core::PluginRegistry.register(:ssg, self)

        def capabilities
          {
            products: {
              exporter: Exporters::ProductsExporter,
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
            "ssg:products:export" => Cli::ExportProducts,
          }
        end

        def products_exporter(client: dependencies[:es_client], **_opts)
          capabilities.dig(:products, :exporter).new(client: client)
        end

        def products_scanner(**opts)
          capabilities.dig(:products, :scanner).new(**opts)
        end
      end
    end
  end
end
