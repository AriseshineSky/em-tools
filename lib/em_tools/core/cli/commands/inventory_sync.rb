# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Core
    module Cli
      module Commands
        # +em-tools inventory sync [config_path]+ — multi-source GCS-CSV -> Elasticsearch sync,
        # delegated to {EmTools::Core::Inventory::SyncRunner.run_from_settings!}.
        #
        # Cluster selection precedence (highest -> lowest):
        #   per-source +cluster:+ in YAML
        #   +inventory_sync.cluster:+ section default
        #   +--data+ flag (defaults sources without +cluster:+ to DATA_ELASTICSEARCH_URL)
        #   ELASTICSEARCH_URL
        class InventorySync < Dry::CLI::Command
          desc "Sync all GCS inventory CSV sources from settings YAML"

          argument :config_path, desc: "Optional path to a settings YAML (default: config/settings.yml)"

          option :data,
            type: :flag,
            default: false,
            desc: "Default sources without cluster: to DATA_ELASTICSEARCH_URL"

          example [
            "                                  # default config/settings.yml",
            "config/staging.yml                # alternate settings file",
            "--data                            # default to data cluster for unmarked sources",
          ]

          def call(config_path: nil, data: false, **)
            EmTools::Core::Cli::Runner.run do
              EmTools::Core::Inventory::SyncRunner.run_from_settings!(
                config_path: config_path,
                prefer_data_cluster: data,
              )
            end
          end
        end
      end
    end
  end
end
