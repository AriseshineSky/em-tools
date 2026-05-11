# frozen_string_literal: true

require "optparse"

module EmTools
  module Core
    module Cli
      module Commands
        # Bulk inventory sync. Reads the +inventory_sync.sources+ list from the merged settings YAML
        # (or an explicit path) and streams every GCS CSV into the inventory ES index.
        class InventorySync
          def run(argv)
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools inventory-sync [path/to/settings.yml]

                Sync all GCS inventory CSV sources listed in the merged settings YAML.
                Requires ELASTICSEARCH_URL; optional GCS_SERVICE_ACCOUNT_PATH.
              BANNER
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
              EmTools::Core::Inventory::SyncRunner.require_elasticsearch_url!

              raw = argv.shift.to_s.strip
              config_path = raw.empty? ? nil : File.expand_path(raw)

              sources = begin
                EmTools::Core::Inventory::SyncSources.load!(config_path)
              rescue EmTools::Core::Inventory::SyncSources::Error => e
                raise EmTools::Core::Errors::ConfigurationError, e.message
              end

              label = config_path || EmTools::Core::SettingsLoader.default_path
              EmTools::Core::Inventory::SyncRunner.new(
                sink: EmTools::Core::Sinks::ElasticsearchBulkSink.new,
                fetcher_opts: EmTools::Core::Inventory::SyncRunner.fetcher_opts_from_env,
              ).run_many!(sources, label: label)
            end
          end
        end
      end
    end
  end
end
