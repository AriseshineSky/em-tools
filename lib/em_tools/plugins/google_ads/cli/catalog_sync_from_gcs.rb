# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module GoogleAds
      module Cli
        # +em-tools google-ads catalog sync-from-gcs [gs://...]+ — single CSV for the ads catalog.
        class CatalogSyncFromGcs < Dry::CLI::Command
          desc "Sync one Google Ads catalog CSV from GCS into Elasticsearch (env-driven)"

          argument :gs_uri,
            desc: "gs://... URI (overrides GOOGLE_ADS_CATALOG_GS_URI / GCS bucket+object env)"

          option :data,
            type: :flag,
            default: false,
            desc: "Bulk-index into DATA_ELASTICSEARCH_URL (falls back to ELASTICSEARCH_URL)"

          example [
            "gs://em-bucket/google-ads-us.csv --data",
            "                                          # uses GOOGLE_ADS_CATALOG_GS_URI",
          ]

          def call(gs_uri: nil, data: false, **)
            EmTools::Core::Cli::Runner.run do
              EmTools::Core::Inventory::SyncRunner.run_one_from_env!(
                cli_gs_uri: gs_uri,
                prefer_data_cluster: data,
                profile: CatalogSyncProfile::PROFILE,
              )
            end
          end
        end
      end
    end
  end
end
