# frozen_string_literal: true

module EmTools
  module Plugins
    module Lotteon
      # Korean marketplace - Lotteon. Produces NDJSON exports against the secondary
      # ("data" / "analytics") Elasticsearch cluster, configured via the +exporters.lotteon_products+
      # block in settings YAML.
      class Plugin < EmTools::Core::Plugin::Base
        def self.plugin_name = :lotteon

        EmTools::Core::PluginRegistry.register(plugin_name, self)

        def capabilities
          {
            products: {
              exporter: Exporters::ProductsExporter,
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

        def products_exporter(client: dependencies[:es_client], **_opts)
          capabilities.dig(:products, :exporter).new(client: client)
        end
      end
    end
  end
end
