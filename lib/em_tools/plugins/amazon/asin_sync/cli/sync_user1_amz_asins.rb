# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Plugins
    module Amazon
      module AsinSync
        module Cli
          # +em-tools amazon asins sync-user1+ — copy new rows from +user1_amz_asins+ on the
          # data cluster into +amz_asins_<marketplace>+ on the primary cluster.
          class SyncUser1AmzAsins < Dry::CLI::Command
            desc "Sync new ASINs from user1_amz_asins (data ES) into amz_asins_<mp> (primary ES)"

            option :source_url,
              aliases: ["--source-url"],
              desc: "Source ES URL (default DATA_ELASTICSEARCH_URL from .env)"
            option :target_url,
              aliases: ["--target-url"],
              desc: "Target ES URL (default ELASTICSEARCH_URL from .env)"
            option :source_index,
              default: User1ToAmzAsinsSync::DEFAULT_SOURCE_INDEX,
              desc: "Source index (default user1_amz_asins)"
            option :full,
              type: :flag,
              default: false,
              desc: "Scan entire source index (no time filter); use for first backfill"
            option :since_hours,
              aliases: ["-H", "--hours"],
              desc: "Incremental window in hours (default 2; override via AMZ_ASIN_SYNC_SINCE_HOURS; ignored with --full)"
            option :time_field,
              default: User1ToAmzAsinsSync::DEFAULT_TIME_FIELD,
              desc: "Source time field for the range filter (default created_at)"
            option :marketplace,
              aliases: ["-m"],
              desc: "Optional marketplace filter (e.g. de, ae)"
            option :bulk_chunk,
              default: User1ToAmzAsinsSync::DEFAULT_BULK_CHUNK.to_s,
              desc: "Batch size for scan/mget/bulk (default 500)"
            option :dry_run,
              type: :flag,
              default: false,
              desc: "Resolve and count only; do not write to target ES"

            example [
              "--full",
              "--since-hours 6",
              "-H 1 -m de",
              "--dry-run",
            ]

            def call(
              source_url: nil,
              target_url: nil,
              source_index: User1ToAmzAsinsSync::DEFAULT_SOURCE_INDEX,
              since_hours: nil,
              time_field: User1ToAmzAsinsSync::DEFAULT_TIME_FIELD,
              marketplace: nil,
              bulk_chunk: User1ToAmzAsinsSync::DEFAULT_BULK_CHUNK.to_s,
              full: false,
              dry_run: false,
              **
            )
              target = resolve_target_url(target_url)
              source = resolve_source_url(source_url)
              raise EmTools::Core::Errors::ConfigurationError, "target URL is required (set ELASTICSEARCH_URL)" if target.empty?
              if source.empty?
                raise EmTools::Core::Errors::ConfigurationError,
                  "source URL is required (set DATA_ELASTICSEARCH_URL or pass --source-url)"
              end

              EmTools::Core::Cli::Runner.run do
                plugin = EmTools::Core::PluginRegistry.fetch(:amazon)
                sync = User1ToAmzAsinsSync.new(
                  source_client: build_client(source),
                  target_client: build_client(target),
                  source_index: source_index,
                  since_hours: resolve_since_hours(since_hours, full: full),
                  time_field: time_field,
                  bulk_chunk: Integer(bulk_chunk),
                  marketplace: marketplace,
                  full_scan: full,
                  dry_run: dry_run,
                  logger: plugin.dependencies[:logger],
                )
                stats = sync.run!
                $stdout.puts(JSON.generate(stats.to_h))
                EmTools::Core::Cli::Runner::Result.new(
                  summary: "user1_amz_asins sync: scanned=#{stats.source_hits} indexed=#{stats.indexed} " \
                    "skipped_existing=#{stats.skipped_existing} skipped_invalid=#{stats.skipped_invalid}",
                )
              end
            end

            private

            def resolve_source_url(cli_url)
              return cli_url.to_s.strip unless cli_url.to_s.strip.empty?

              EmTools::Core::Config.data_elasticsearch_url.to_s
            end

            def resolve_target_url(cli_url)
              return cli_url.to_s.strip unless cli_url.to_s.strip.empty?

              EmTools::Core::Config.elasticsearch_url
            rescue RuntimeError
              ""
            end

            def build_client(url)
              EmTools::Core::Config.elasticsearch_client(url: url)
            end

            # CLI (-H / --since-hours) wins, then AMZ_ASIN_SYNC_SINCE_HOURS, then 2.
            def resolve_since_hours(cli_value, full:)
              return User1ToAmzAsinsSync::DEFAULT_SINCE_HOURS if full

              raw = cli_value.to_s.strip
              raw = ENV["AMZ_ASIN_SYNC_SINCE_HOURS"].to_s.strip if raw.empty?
              raw = User1ToAmzAsinsSync::DEFAULT_SINCE_HOURS.to_s if raw.empty?
              hours = Float(raw)
              raise EmTools::Core::Errors::ConfigurationError, "since-hours must be > 0" unless hours.positive?

              hours
            rescue ArgumentError
              raise EmTools::Core::Errors::ConfigurationError,
                "since-hours must be a number (got #{raw.inspect})"
            end
          end
        end
      end
    end
  end
end
