# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Cli
          # +em-tools amazon products format-file PRODUCTS_PATH+ — Ruby port of em-celery
          # +amz_uploadable_products_formatter_from_file.py+ (+filter_products+).
          # Reads ASINs (one per line), looks up product + offer docs from Elasticsearch
          # via +mget+, and writes formatted rows to NDJSON (-o) and/or bulk-indexes them
          # (--to-es). At least one of -o / --to-es must be set.
          class AmzUploadableProductsFormatterFromFile < Dry::CLI::Command
            desc "Format ASIN-based product+offer rows to NDJSON and/or bulk-index"

            argument :products_path, required: true, desc: "Path to ASIN list (one per line)"

            option :store_code, aliases: ["-s"], desc: "Store code (required; same as Python -s)"
            option :marketplace, aliases: ["-m"], default: "us", desc: "Amazon marketplace (default: us)"
            option :output,
              aliases: ["-o"],
              desc: "Output NDJSON path (required unless --to-es; same as Python -o)"
            option :so, desc: "Product source (required; Python -so). e.g. AMZ_US"
            option :sc, desc: "Product source code (required; Python -sc)"
            # rubocop:enable Layout/LineLength
            option :export,
              aliases: ["-e"],
              type: :flag,
              default: false,
              desc: "Whether to export products to other countries (Python -e)"
            option :ttl,
              aliases: ["-t"],
              default: "30",
              desc: "Offer TTL days (default: 30; informational)"
            option :product_index, desc: "Override product ES index (default: amz_products_api_<mp>_v2)"
            option :offer_index, desc: "Override offer ES index (default: lowest_offer_listings_<mp>_new)"
            option :emitter_dir, desc: "Sidecar stats directory (default: ~/.em_tasks/amz_<mp>)"
            option :skip_offers,
              type: :flag,
              default: false,
              desc: "Do not mget offer index; use price/currency from product _source"
            option :batch_size, default: "500", desc: "ASINs per mget batch (default: 500)"
            option :to_es,
              type: :flag,
              default: false,
              desc: "Bulk-index formatted rows into Elasticsearch (in addition to or instead of -o)"
            option :sink_index, desc: "Destination ES index for --to-es (default: amz_uploadable_products_<mp>)"
            option :bulk_chunk, default: "500", desc: "Documents per bulk request (default: 500)"
            option :refresh, type: :flag, default: false, desc: "Refresh sink index after run (--to-es only)"
            option :dry_run,
              type: :flag,
              default: false,
              desc: "Resolve and process but skip ES bulk writes (file output still written)"

            example [
              "products.txt -s MYSTORE -m us -o out.ndjson --so AMZ_US --sc wholesale",
              "asins.txt -s MYSTORE -m de --to-es --so SRC --sc CODE --skip-offers",
            ]

            def call(products_path:, store_code: nil, marketplace: "us", output: nil,
              so: nil, sc: nil, export: false, ttl: "30", product_index: nil,
              offer_index: nil, emitter_dir: nil, skip_offers: false, batch_size: "500",
              to_es: false, sink_index: nil, bulk_chunk: "500", refresh: false,
              dry_run: false, **)
              validate!(store_code: store_code, source: so, source_code: sc, output: output, to_es: to_es)
              EmTools::Core::Cli::Support.require_elasticsearch_url!

              resolved_sink = if to_es
                s = sink_index.to_s.strip
                s.empty? ? "amz_uploadable_products_#{marketplace}" : s
              end

              plugin = EmTools::Core::PluginRegistry.fetch(:amazon)
              formatter = plugin.products_formatter(
                marketplace: marketplace,
                products_path: products_path,
                output_path: output,
                source: so,
                source_code: sc,
                store_code: store_code,
                export: export,
                ttl: Integer(ttl),
                product_index: product_index,
                offer_index: offer_index,
                emitter_dir: emitter_dir,
                batch_size: Integer(batch_size),
                skip_offers: skip_offers,
                sink_index: resolved_sink,
                sink_bulk_chunk_lines: Integer(bulk_chunk),
                sink_refresh: refresh,
                dry_run: dry_run,
              )

              formatter.run!(client: plugin.dependencies[:es_client])
              warn(JSON.generate(
                sink_index: formatter.sink_index,
                output_path: formatter.output_path,
                record: formatter.record,
              ))
            end
            # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

            private

            def validate!(store_code:, source:, source_code:, output:, to_es:)
              missing = []
              missing << "-s / --store-code" if store_code.to_s.strip.empty?
              missing << "--so (source)" if source.to_s.strip.empty?
              missing << "--sc (source-code)" if source_code.to_s.strip.empty?
              missing << "-o / --output (or --to-es / --sink-index)" if output.to_s.strip.empty? && !to_es
              return if missing.empty?

              warn("error: missing required option(s): #{missing.join(", ")}")
              exit(1)
            end
          end
        end
      end
    end
  end
end
