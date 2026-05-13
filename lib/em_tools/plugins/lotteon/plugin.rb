# frozen_string_literal: true

module EmTools
  module Plugins
    module Lotteon
      # Korean marketplace - Lotteon. Produces NDJSON exports against the secondary
      # ("data" / "analytics") Elasticsearch cluster, configured via the +exporters.lotteon_products+
      # block in settings YAML.
      class Plugin < EmTools::Core::Plugin::Base
        EmTools::Core::PluginRegistry.register(:lotteon, self)

        def cli_commands
          {
            "lotteon:export-products" => Cli::ExportProducts,
          }
        end

        def products_exporter(**opts)
          Exporters::ProductsExporter.new(**opts)
        end
      end
    end
  end
end
