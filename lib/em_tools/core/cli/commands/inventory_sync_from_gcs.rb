# frozen_string_literal: true

require "optparse"

module EmTools
  module Core
    module Cli
      module Commands
        # Thin CLI wrapper over {EmTools::Core::Inventory::SyncRunner.run_one_from_env!}.
        class InventorySyncFromGcs
          def run(argv)
            options = { use_data_cluster: false }

            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools inventory-sync-from-gcs [--data] [gs://bucket/path.csv]

                Sync one inventory CSV from GCS into Elasticsearch.
                URI: argument, or INVENTORY_GS_URI, or INVENTORY_GCS_BUCKET + INVENTORY_GCS_OBJECT.

                Cluster: defaults to ELASTICSEARCH_URL. Pass --data to target
                DATA_ELASTICSEARCH_URL instead (falls back to ELASTICSEARCH_URL when unset).

                Env: INVENTORY_INDEX, INVENTORY_REFRESH=1, INVENTORY_PRUNE_OBSOLETE=1,
                     INVENTORY_FEED_ID, INVENTORY_DROP_FIELDS (comma-separated; e.g. "handle,variants").
              BANNER
              opts.on("--data", "Bulk-index into DATA_ELASTICSEARCH_URL") { options[:use_data_cluster] = true }
              opts.on_tail("-h", "--help") do
                puts opts
                exit(0)
              end
            end
            parser.parse!(argv)

            gs_uri_arg = argv.shift
            unless argv.empty?
              warn("error: unexpected arguments: #{argv.join(" ")}")
              exit(1)
            end

            EmTools::Core::Cli::Runner.run do
              EmTools::Core::Inventory::SyncRunner.run_one_from_env!(
                cli_gs_uri: gs_uri_arg,
                prefer_data_cluster: options[:use_data_cluster],
              )
            end
          end
        end
      end
    end
  end
end
