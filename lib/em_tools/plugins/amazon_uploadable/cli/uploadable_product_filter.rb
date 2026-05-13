# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Plugins
    module AmazonUploadable
      module Cli
        # +em-tools amz-uploadable filter+ — phase-1 Ruby port of em-tasks
        # +amazon.uploadable_product_filter+. Streams ASINs from
        # +amz_asins_<marketplace>+ and either prints them or bulk-indexes them.
        class UploadableProductFilter < Dry::CLI::Command
          desc "Stream uploadable ASINs from the Amazon ASIN index"

          option :marketplace, aliases: ["-m"], default: "us", desc: "Amazon marketplace (default: us)"
          option :ttl, aliases: ["-t"], default: "30", desc: "Offer TTL days (default: 30, informational)"
          option :asin_since_days, default: "7", desc: "Relative window without absolute cutoff (default: 7)"
          option :asin_time_field, desc: "auto|timestamp|created_at|time"
          option :asin_cutoff, desc: "Absolute cutoff (time_field > cutoff)"
          option :asin_label, desc: "Optional term filter on label field"
          option :asin_label_field, desc: "ES field for label term (default: label)"
          option :config, desc: "YAML file merged into stream option resolution"
          option :dry_run,
            type: :flag,
            default: false,
            desc: "Skip side effects (stdout: print resolved config; --to-es: skip bulk)"
          option :max_asins, desc: "Stop after N ASINs (testing)"
          option :to_es,
            type: :flag,
            default: false,
            desc: "Bulk-index matched ASINs into Elasticsearch instead of stdout"
          option :sink_index, desc: "Destination ES index for --to-es (default: amz_uploadable_asins_<mp>)"
          option :bulk_chunk, default: "500", desc: "Documents per bulk request (default: 500)"
          option :refresh, type: :flag, default: false, desc: "Refresh sink index after run (--to-es only)"

          example [
            "-m de --asin-since-days 1",
            "-m de --dry-run",
            "-m de --to-es --sink-index amz_uploadable_asins_de --bulk-chunk 1000 --refresh",
          ]

          def call(marketplace: "us", ttl: "30", asin_since_days: "7", asin_time_field: nil,
            asin_cutoff: nil, asin_label: nil, asin_label_field: nil, config: nil,
            dry_run: false, max_asins: nil, to_es: false, sink_index: nil,
            bulk_chunk: "500", refresh: false, **)
            EmTools::Core::Cli::Support.require_elasticsearch_url!
            cfg = config ? EmTools::Core::Cli::Support.load_yaml_file!(config) : {}

            plugin = EmTools::Core::PluginRegistry.fetch(:amazon_uploadable)
            filter = plugin.uploadable_product_filter(
              marketplace: marketplace,
              ttl: Integer(ttl),
              asin_since_days: Integer(asin_since_days),
              asin_time_field: asin_time_field,
              asin_cutoff: asin_cutoff,
              asin_label: asin_label,
              asin_label_field: asin_label_field,
              config: cfg,
            )

            if dry_run && !to_es
              $stdout.puts(JSON.generate(filter.describe))
              return
            end

            client = plugin.dependencies[:es_client]
            max = max_asins ? Integer(max_asins) : nil

            if to_es
              stats = filter.bulk_index_asins!(
                client: client,
                sink_index: sink_index,
                max_asins: max,
                bulk_chunk_lines: Integer(bulk_chunk),
                dry_run: dry_run,
                refresh: refresh,
              )
              resolved = sink_index.to_s.strip
              resolved = filter.default_sink_index if resolved.empty?
              warn(JSON.generate(sink_index: resolved, stats: stats.to_h, dry_run: dry_run))
              return
            end

            filter.stream_asins!(client: client, max_asins: max)
          end
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
        end
      end
    end
  end
end
