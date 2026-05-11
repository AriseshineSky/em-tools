# frozen_string_literal: true

require "optparse"

module EmTools
  module Core
    module Cli
      module Commands
        # Single-object GCS inventory sync: pulls one CSV from GCS and bulk-indexes it into the
        # inventory ES index (debug helper that bypasses the +settings.yml+ multi-source path).
        class InventorySyncFromGcs
          def run(argv)
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools inventory-sync-from-gcs [gs://bucket/path.csv]

                Sync one inventory CSV from GCS into Elasticsearch.
                URI: argument, or INVENTORY_GS_URI, or INVENTORY_GCS_BUCKET + INVENTORY_GCS_OBJECT.

                Env: ELASTICSEARCH_URL (required), INVENTORY_INDEX, INVENTORY_REFRESH=1,
                INVENTORY_PRUNE_OBSOLETE=1, INVENTORY_FEED_ID.
              BANNER
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
              EmTools::Core::Inventory::SyncRunner.require_elasticsearch_url!

              gs_uri = EmTools::Core::Inventory::SyncRunner.resolve_single_gs_uri(cli_gs_uri: gs_uri_arg)
              feed_id = ENV["INVENTORY_FEED_ID"].to_s.strip
              feed_id = gs_uri if feed_id.empty?

              EmTools::Core::Inventory::SyncRunner.new(
                sink: EmTools::Core::Sinks::ElasticsearchBulkSink.new,
                fetcher_opts: EmTools::Core::Inventory::SyncRunner.fetcher_opts_from_env,
              ).run_one!(
                gs_uri: gs_uri,
                index: ENV.fetch("INVENTORY_INDEX", EmTools::Core::Inventory::Sync::INDEX),
                feed_id: feed_id,
                refresh: ENV["INVENTORY_REFRESH"] == "1",
                prune_obsolete: ENV["INVENTORY_PRUNE_OBSOLETE"] == "1",
              )

              EmTools::Core::Cli::Runner::Result.new(summary: "Inventory sync done.")
            end
          end
        end
      end
    end
  end
end
