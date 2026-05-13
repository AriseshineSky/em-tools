# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Plugins
    module AmazonUploadable
      module Cli
        # +em-tools amz-uploadable asin-to-es+ — stream ASINs from the ASIN index, mget
        # product docs, filter, then bulk-write enriched docs to a sink ES index.
        class AsinProductsToEs < Dry::CLI::Command
          desc "Enrich ASINs with product docs (mget) and bulk-write to a sink index"

          option :marketplace, aliases: ["-m"], default: "us", desc: "Marketplace (default: us)"
          option :product_index, desc: "Product API index (default: amz_products_api_<mp>_v2)"
          option :sink_index, desc: "Required. Destination index for enriched documents"
          option :config, desc: "YAML merged into ASIN stream resolution"
          option :min_price, desc: "Minimum numeric price after resolution"
          option :max_price, desc: "Maximum numeric price"
          option :require_fields, desc: "Comma-separated _source fields that must be non-empty"
          option :keywords_path, desc: "Optional blacklist keywords (title substring match)"
          option :title_field, default: "title", desc: "Product field for blacklist scan (default: title)"
          option :asin_batch_size, default: "100", desc: "ASINs per mget batch (default: 100)"
          option :bulk_chunk, default: "200", desc: "Docs per bulk request (default: 200)"
          option :dry_run, type: :flag, default: false, desc: "Resolve + filter but skip bulk index"
          option :max_asin_hits, desc: "Stop after N ASIN hits (testing)"
          option :asin_since_days, default: "7", desc: "ASIN stream relative window (default: 7)"
          option :asin_time_field, desc: "auto|timestamp|created_at|time"
          option :asin_cutoff, desc: "Absolute ISO8601 cutoff"
          option :asin_label, desc: "Optional term filter on label field"
          option :asin_label_field, desc: "ES field for label term"

          example [
            "-m de --sink-index amz_enriched_products_de --min-price 10 --max-price 500 --dry-run",
            "-m de --sink-index amz_enriched_products_de --config tmp/pipeline.yml --max-asin-hits 500",
          ]

          def call(marketplace: "us", product_index: nil, sink_index: nil, config: nil,
            min_price: nil, max_price: nil, require_fields: nil, keywords_path: nil,
            title_field: "title", asin_batch_size: "100", bulk_chunk: "200",
            dry_run: false, max_asin_hits: nil, asin_since_days: "7",
            asin_time_field: nil, asin_cutoff: nil, asin_label: nil, asin_label_field: nil, **)
            if sink_index.to_s.strip.empty?
              warn("error: --sink-index is required")
              exit(1)
            end

            EmTools::Core::Cli::Support.require_elasticsearch_url!
            cfg = config ? EmTools::Core::Cli::Support.load_yaml_file!(config) : {}
            keywords = keywords_path ? EmTools::Core::Cli::Support.load_keywords(keywords_path) : []
            req = require_fields.to_s.split(",").map(&:strip).reject(&:empty?)

            plugin = EmTools::Core::PluginRegistry.fetch(:amazon_uploadable)
            filter = plugin.uploadable_product_filter(
              marketplace: marketplace,
              config: cfg,
              asin_since_days: Integer(asin_since_days),
              asin_time_field: asin_time_field,
              asin_cutoff: asin_cutoff,
              asin_label: asin_label,
              asin_label_field: asin_label_field,
            )

            pipeline = plugin.asin_product_pipeline(
              marketplace: marketplace,
              sink_index: sink_index,
              product_index: product_index,
              filter: filter,
              min_price: min_price ? Float(min_price) : nil,
              max_price: max_price ? Float(max_price) : nil,
              require_product_fields: req,
              keywords: keywords,
              title_field: title_field,
              asin_batch_size: Integer(asin_batch_size),
              bulk_chunk_lines: Integer(bulk_chunk),
              max_asin_hits: max_asin_hits ? Integer(max_asin_hits) : nil,
            )

            stats = pipeline.run!(client: plugin.dependencies[:es_client], dry_run: dry_run)
            $stdout.puts(JSON.generate(stats.to_h))
          end
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
        end
      end
    end
  end
end
