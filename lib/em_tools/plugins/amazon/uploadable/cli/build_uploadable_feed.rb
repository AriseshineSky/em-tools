# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Cli
          # +em-tools amazon products build-feed+ builds final uploadable feed rows
          # from either local ASIN seeds or an Elasticsearch ASIN index, then writes
          # the records to stdout, local JSONL, Elasticsearch, or both file + ES.
          class BuildUploadableFeed < Dry::CLI::Command
            desc "Build Amazon uploadable feed rows from file or Elasticsearch seeds"

            option :marketplace, aliases: ["-m"], default: "us", desc: "Amazon marketplace (default: us)"
            option :seed_source, default: "es", desc: "ASIN seed source: es|file (default: es)"
            option :seed_path, desc: "ASIN seed file path when --seed-source=file"
            option :seed_index, desc: "ASIN seed ES index when --seed-source=es (default: amz_asins_<mp>)"
            option :config, desc: "YAML merged into ASIN stream option resolution"
            option :store_code, aliases: ["-s"], desc: "Optional store code"
            option :so, desc: "Product source (default: AMZ_<MP>)"
            option :sc, desc: "Product source code"
            option :export, aliases: ["-e"], type: :flag, default: false, desc: "Mark rows as exportable"
            option :ttl, aliases: ["-t"], default: "30", desc: "Offer TTL days (default: 30)"
            option :product_index, desc: "Product ES index (default: amz_products_api_<mp>_v2)"
            option :offer_index, desc: "Offer ES index (default: lowest_offer_listings_<mp>_new)"
            option :skip_offers, type: :flag, default: false, desc: "Use product price/currency instead of offer index"
            option :batch_size, default: "500", desc: "ASINs per mget batch (default: 500)"
            option :output, aliases: ["-o"], desc: "Write JSONL feed rows to this file"
            option :sink_index, desc: "Also bulk-index feed rows into this ES index"
            option :bulk_chunk, default: "500", desc: "Rows per ES bulk request (default: 500)"
            option :refresh, type: :flag, default: false, desc: "Refresh --sink-index after run"
            option :max_asins, desc: "Stop after N ASIN seeds (testing)"
            option :asin_since_days, default: "7", desc: "ES seed relative window (default: 7)"
            option :asin_time_field, desc: "ES seed time field: auto|timestamp|created_at|time"
            option :asin_cutoff, desc: "ES seed absolute ISO8601 cutoff"
            option :asin_label, desc: "Optional ES seed label term"
            option :asin_label_field, desc: "ES seed label field (default: label)"
            option :dry_run, type: :flag, default: false, desc: "Print resolved manifest JSON and exit"

            example [
              "-m de --dry-run",
              "-m de --output tmp/feed.de.ndjson",
              "-m de --sink-index amz_uploadable_products_de --refresh",
              "-m de --seed-source=file --seed-path tmp/asins.de.txt -o tmp/feed.de.ndjson",
              "-m de --seed-source=file --seed-path tmp/asins.de.txt --sink-index amz_uploadable_products_de",
            ]

            def call(marketplace: "us", seed_source: "es", seed_path: nil, seed_index: nil,
              config: nil, store_code: nil, so: nil, sc: nil, export: false, ttl: "30",
              product_index: nil, offer_index: nil, skip_offers: false, batch_size: "500",
              output: nil, sink_index: nil, bulk_chunk: "500", refresh: false, max_asins: nil,
              asin_since_days: "7", asin_time_field: nil, asin_cutoff: nil, asin_label: nil,
              asin_label_field: nil, dry_run: false, **)
              EmTools::Core::Cli::Runner.run do
                cfg = config ? EmTools::Core::Cli::Support.load_yaml_file!(config) : {}
                plugin = EmTools::Core::PluginRegistry.fetch(:amazon)
                source = plugin.uploadable_asin_source(
                  kind: seed_source,
                  marketplace: marketplace,
                  path: seed_path,
                  index: seed_index,
                  max_asins: integer_or_nil(max_asins),
                  ttl: Integer(ttl),
                  config: cfg,
                  asin_since_days: Integer(asin_since_days),
                  asin_time_field: asin_time_field,
                  asin_cutoff: asin_cutoff,
                  asin_label: asin_label,
                  asin_label_field: asin_label_field,
                  dry_run: dry_run,
                )
                sink = plugin.uploadable_feed_sink(
                  output_path: output,
                  sink_index: sink_index,
                  bulk_chunk: Integer(bulk_chunk),
                  refresh: refresh,
                  dry_run: dry_run,
                )

                operation = plugin.build_uploadable_feed(
                  marketplace: marketplace,
                  source: source,
                  sink: sink,
                  listing_source: so,
                  source_code: sc,
                  store_code: store_code,
                  export: export,
                  ttl: Integer(ttl),
                  product_index: product_index,
                  offer_index: offer_index,
                  skip_offers: skip_offers,
                  batch_size: Integer(batch_size),
                  dry_run: dry_run,
                )

                result = operation.run!
                $stdout.puts(JSON.generate(result)) if dry_run
                warn(JSON.generate(result)) unless dry_run
              end
            end

            private

            def integer_or_nil(value)
              value.to_s.strip.empty? ? nil : Integer(value)
            end
          end
        end
      end
    end
  end
end
