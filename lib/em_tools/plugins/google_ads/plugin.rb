# frozen_string_literal: true

module EmTools
  module Plugins
    module GoogleAds
      # Google Ads product catalog: GCS CSV → Elasticsearch (advertised SKU subset).
      class Plugin < EmTools::Core::Plugin::Base
        def self.plugin_name = :google_ads

        EmTools::Core::PluginRegistry.register(plugin_name, self)

        def cli_commands
          {
            "catalog sync" => Cli::CatalogSync,
            "catalog sync-from-gcs" => Cli::CatalogSyncFromGcs,
            "catalog missing-product-ids" => Cli::MissingProductIds,
            "catalog asin-categories" => Cli::AsinCategories,
          }
        end
      end
    end
  end
end
