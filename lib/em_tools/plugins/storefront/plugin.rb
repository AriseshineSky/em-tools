# frozen_string_literal: true

module EmTools
  module Plugins
    module Storefront
      # User-owned storefront (Spree-derived). Source/sink for product / inventory / offer data
      # consumed by other plugins; exposes the +product-importer+ CLI for filtering local CSV /
      # JSON product feeds against the rule engine.
      class Plugin < EmTools::Core::Plugin::Base
        EmTools::Core::PluginRegistry.register(:storefront, self)

        def cli_commands
          {
            "import-products" => Cli::ImportProducts,
            "storefront-sync-inventory" => Cli::SyncInventory,
            "storefront-unpublish-candidates" => Cli::UnpublishCandidates,
          }
        end

        def product_util(**opts)
          ProductUtil.new(**opts)
        end

        def product_importer(**opts)
          Importers::ProductImporter.new(**opts)
        end

        def sync_inventory(**opts)
          Runners::SyncInventory.new(**opts)
        end

        def unpublish_candidates(**opts)
          Runners::UnpublishCandidates.new(**opts)
        end
      end
    end
  end
end
