# frozen_string_literal: true

module EmTools
  module Core
    module Cli
      # Canonical command names for the built-in CLI surface.
      #
      # Keep command strings here so renames and aliases are explicit rather
      # than scattered across the runtime dispatcher, help renderer, docs, and
      # specs.
      module CommandNames
        DUMP = "dump"
        ES_DUMP_INDEX = "es-dump-index"
        ES_DOWNLOAD_PRODUCT = "es-download-product"
        INVENTORY_SYNC = "inventory-sync"
        INVENTORY_SYNC_FROM_GCS = "inventory-sync-from-gcs"
        GCS_DOWNLOAD_SEEDS = "gcs-download-seeds"
        LOWEST_OFFER_PUBLISH_SNAPSHOT = "lowest-offer-publish-snapshot"
        LOWEST_OFFER_DOWNLOAD_AND_PUBLISH = "lowest-offer-download-and-publish"
        EBAY_LISTINGS_PUBLISH_SNAPSHOT = "ebay-listings-publish-snapshot"

        # Namespace-style aliases preserve today's hyphenated command names
        # while giving us a path toward grouped commands later.
        ALIASES = {
          "es:dump-index" => ES_DUMP_INDEX,
          "es:download-product" => ES_DOWNLOAD_PRODUCT,
          "inventory:sync" => INVENTORY_SYNC,
          "inventory:sync-from-gcs" => INVENTORY_SYNC_FROM_GCS,
          "gcs:download-seeds" => GCS_DOWNLOAD_SEEDS,
          "lowest-offer:publish-snapshot" => LOWEST_OFFER_PUBLISH_SNAPSHOT,
          "lowest-offer:download-and-publish" => LOWEST_OFFER_DOWNLOAD_AND_PUBLISH,
          "ebay-listings:publish-snapshot" => EBAY_LISTINGS_PUBLISH_SNAPSHOT,
        }.freeze
      end
    end
  end
end
