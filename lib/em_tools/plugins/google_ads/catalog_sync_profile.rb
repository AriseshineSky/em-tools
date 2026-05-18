# frozen_string_literal: true

module EmTools
  module Plugins
    module GoogleAds
      # Google Ads / Merchant product catalog sync — subset shown in ads, not full-site inventory.
      class CatalogSyncProfile
        PROFILE = EmTools::Core::Inventory::SyncProfile.new(
          settings_key: "google_ads_catalog_sync",
          env_prefix: "GOOGLE_ADS_CATALOG_",
          default_index: "google_ads_products",
          default_gs_uri: "gs://em-bucket/google-ads-catalog.csv",
          feed_field: "google_ads_feed",
          config_label: "google_ads_catalog_sync",
        )
      end
    end
  end
end
