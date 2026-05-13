# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Core
    module Cli
      module Commands
        # +em-tools inventory sync-from-gcs [gs://bucket/path.csv]+ — single-CSV variant.
        # Reads INVENTORY_* env vars; +--data+ targets DATA_ELASTICSEARCH_URL.
        class InventorySyncFromGcs < Dry::CLI::Command
          desc "Sync one inventory CSV from GCS into Elasticsearch (env-driven)"

          argument :gs_uri,
            desc: "gs://... URI (overrides INVENTORY_GS_URI / INVENTORY_GCS_BUCKET+OBJECT)"

          option :data,
            type: :flag,
            default: false,
            desc: "Bulk-index into DATA_ELASTICSEARCH_URL (falls back to ELASTICSEARCH_URL)"

          example [
            "gs://em-bucket/Ebay_US-Inv.csv --data",
            "                                          # uses INVENTORY_GS_URI",
          ]

          def call(gs_uri: nil, data: false, **)
            EmTools::Core::Cli::Runner.run do
              EmTools::Core::Inventory::SyncRunner.run_one_from_env!(
                cli_gs_uri: gs_uri,
                prefer_data_cluster: data,
              )
            end
          end
        end
      end
    end
  end
end
