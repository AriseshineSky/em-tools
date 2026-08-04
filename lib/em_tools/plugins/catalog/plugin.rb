# frozen_string_literal: true

module EmTools
  module Plugins
    module Catalog
      # Cross-channel catalog_products sync (Docmorris, …).
      class Plugin < EmTools::Core::Plugin::Base
        def self.plugin_name = :catalog

        EmTools::Core::PluginRegistry.register(plugin_name, self)

        def capabilities
          {
            product_sync: {
              docmorris: ProductSync::User1DocmorrisToCatalogProductsSync,
            },
          }
        end

        def dependencies
          @dependencies ||= {
            es_client: EmTools::Clients::ElasticsearchClient.new,
            logger: EmTools::Core::Logger.for(progname: "catalog"),
          }
        end

        def cli_commands
          {
            "products sync-docmorris" => ProductSync::Cli::SyncDocmorrisProducts,
          }
        end
      end
    end
  end
end
