# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Plugins
    module Catalog
      module ProductSync
        module Cli
          # +em-tools catalog products sync-docmorris+ — project Docmorris crawl
          # rows from +user1_de_products+ (data ES) into +catalog_products+ (primary).
          class SyncDocmorrisProducts < Dry::CLI::Command
            desc "Sync Docmorris products from user1_de_products (data ES) into catalog_products (primary ES)"

            option :source_url,
              aliases: ["--source-url"],
              desc: "Source ES URL (default DATA_ELASTICSEARCH_URL from .env)"
            option :target_url,
              aliases: ["--target-url"],
              desc: "Target ES URL (default ELASTICSEARCH_URL from .env)"
            option :source_index,
              default: User1DocmorrisToCatalogProductsSync::DEFAULT_SOURCE_INDEX,
              desc: "Source index (default user1_de_products)"
            option :target_index,
              default: User1DocmorrisToCatalogProductsSync::DEFAULT_TARGET_INDEX,
              desc: "Target index (default catalog_products)"
            option :full,
              type: :flag,
              default: false,
              desc: "Scan entire source (no time filter); use for first backfill"
            option :since_hours,
              aliases: ["-H", "--hours"],
              desc: "Incremental window in hours (default 36; ignored with --full or --since-date)"
            option :since_date,
              aliases: ["--after", "--date"],
              desc: "Only sync docs with time_field > this ISO8601 date"
            option :before_date,
              aliases: ["--until", "--before"],
              desc: "Only sync docs with time_field < this ISO8601 date"
            option :time_field,
              default: User1DocmorrisToCatalogProductsSync::DEFAULT_TIME_FIELD,
              desc: "Source time field for the range filter (default date)"
            option :bulk_chunk,
              default: User1DocmorrisToCatalogProductsSync::DEFAULT_BULK_CHUNK.to_s,
              desc: "Batch size for scan/mget/bulk (default 500)"
            option :skip_missing,
              type: :flag,
              default: false,
              desc: "Update only documents that already exist in the target index"
            option :dry_run,
              type: :flag,
              default: false,
              desc: "Resolve and count only; do not write to target ES"
            option :sample_dir,
              default: User1DocmorrisToCatalogProductsSync::DEFAULT_SAMPLE_DIR,
              desc: "Directory for _id/date checkpoint TSV files (empty to disable)"
            option :sample_interval,
              default: User1DocmorrisToCatalogProductsSync::DEFAULT_SAMPLE_INTERVAL.to_s,
              desc: "Write one checkpoint file every N indexed docs (default 1000)"
            option :no_samples,
              type: :flag,
              default: false,
              desc: "Disable local _id/date checkpoint files"
            option :debug,
              type: :flag,
              default: false,
              desc: "Log per-batch debug details"

            example [
              "--since-hours 36",
              "--full",
              "--dry-run",
              "--since-date 2026-05-18T14:45:15+00:00",
            ]

            def call(
              source_url: nil,
              target_url: nil,
              source_index: User1DocmorrisToCatalogProductsSync::DEFAULT_SOURCE_INDEX,
              target_index: User1DocmorrisToCatalogProductsSync::DEFAULT_TARGET_INDEX,
              since_hours: nil,
              since_date: nil,
              before_date: nil,
              time_field: User1DocmorrisToCatalogProductsSync::DEFAULT_TIME_FIELD,
              bulk_chunk: User1DocmorrisToCatalogProductsSync::DEFAULT_BULK_CHUNK.to_s,
              full: false,
              skip_missing: false,
              dry_run: false,
              sample_dir: User1DocmorrisToCatalogProductsSync::DEFAULT_SAMPLE_DIR,
              sample_interval: User1DocmorrisToCatalogProductsSync::DEFAULT_SAMPLE_INTERVAL.to_s,
              no_samples: false,
              debug: false,
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
                plugin = EmTools::Core::PluginRegistry.fetch(:catalog)
                sync = User1DocmorrisToCatalogProductsSync.new(
                  source_client: build_client(source),
                  target_client: build_client(target),
                  source_index: source_index,
                  target_index: target_index,
                  since_hours: resolve_since_hours(since_hours, full: full, since_date: since_date),
                  since_date: since_date,
                  before_date: before_date,
                  time_field: time_field,
                  bulk_chunk: Integer(bulk_chunk),
                  full_scan: full,
                  skip_missing: skip_missing,
                  dry_run: dry_run,
                  sample_dir: no_samples ? nil : sample_dir,
                  sample_interval: Integer(sample_interval),
                  debug: debug,
                  logger: plugin.dependencies[:logger],
                )
                stats = sync.run!
                $stdout.puts(JSON.generate(stats.to_h))
                EmTools::Core::Cli::Runner::Result.new(
                  summary: "docmorris catalog sync: scanned=#{stats.source_hits} indexed=#{stats.indexed} " \
                    "skipped_stale=#{stats.skipped_stale} skipped_missing=#{stats.skipped_missing} " \
                    "skipped_invalid=#{stats.skipped_invalid} sample_files=#{stats.sample_files} " \
                    "sample_rows=#{stats.sample_rows}",
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

            def resolve_since_hours(cli_value, full:, since_date:)
              return User1DocmorrisToCatalogProductsSync::DEFAULT_SINCE_HOURS if full
              return User1DocmorrisToCatalogProductsSync::DEFAULT_SINCE_HOURS unless since_date.to_s.strip.empty?

              raw = cli_value.to_s.strip
              raw = ENV["CATALOG_DOCMORRIS_SYNC_SINCE_HOURS"].to_s.strip if raw.empty?
              raw = User1DocmorrisToCatalogProductsSync::DEFAULT_SINCE_HOURS.to_s if raw.empty?
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
