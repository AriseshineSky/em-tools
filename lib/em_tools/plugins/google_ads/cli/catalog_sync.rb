# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module GoogleAds
      module Cli
        # +em-tools google-ads catalog sync [config_path]+ — multi-source GCS CSV sync for the
        # Google Ads product catalog (not full-site inventory).
        class CatalogSync < Dry::CLI::Command
          desc "Sync all Google Ads catalog CSV sources from settings YAML"

          argument :config_path, desc: "Optional path to a settings YAML (default: config/settings.yml)"

          option :data,
            type: :flag,
            default: false,
            desc: "Default sources without cluster: to DATA_ELASTICSEARCH_URL"

          example [
            "                                  # default config/settings.yml",
            "config/staging.yml --data",
          ]

          def call(config_path: nil, data: false, **)
            EmTools::Core::Cli::Runner.run do
              EmTools::Core::Inventory::SyncRunner.run_from_settings!(
                config_path: config_path,
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
