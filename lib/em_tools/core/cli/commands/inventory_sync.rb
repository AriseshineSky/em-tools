# frozen_string_literal: true

require "optparse"

module EmTools
  module Core
    module Cli
      module Commands
        # Thin CLI wrapper over {EmTools::Core::Inventory::SyncRunner.run_from_settings!}.
        class InventorySync
          def run(argv)
            options = { use_data_cluster: false }

            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools inventory-sync [--data] [path/to/settings.yml]

                Sync all GCS inventory CSV sources listed in the merged settings YAML.

                Each source can declare its own cluster in YAML:
                  - per-source `cluster: primary|data|<name>` (always wins)
                  - `inventory_sync.cluster: ...`             (section default)
                  - --data                                    (runtime default for sources without `cluster:`)
                  - otherwise falls back to ELASTICSEARCH_URL.
              BANNER
              opts.on("--data", "Default to DATA_ELASTICSEARCH_URL for sources without cluster:") do
                options[:use_data_cluster] = true
              end
              opts.on_tail("-h", "--help") do
                puts opts
                exit(0)
              end
            end
            parser.parse!(argv)

            if argv.size > 1
              warn("error: at most one optional path to settings YAML")
              exit(1)
            end

            EmTools::Core::Cli::Runner.run do
              EmTools::Core::Inventory::SyncRunner.run_from_settings!(
                config_path: argv.shift,
                prefer_data_cluster: options[:use_data_cluster],
              )
            end
          end
        end
      end
    end
  end
end
