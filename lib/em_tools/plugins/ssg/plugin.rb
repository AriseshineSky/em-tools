# frozen_string_literal: true

module EmTools
  module Plugins
    module Ssg
      # Korean marketplace - SSG. Bundles the products NDJSON exporter and the keyword scanner.
      class Plugin < EmTools::Core::Plugin::Base
        EmTools::Core::PluginRegistry.register(:ssg, self)

        def products_exporter(**opts)
          Exporters::ProductsExporter.new(**opts)
        end

        def products_scanner(**opts)
          Scanners::ProductsScanner.new(**opts)
        end
      end
    end
  end
end
