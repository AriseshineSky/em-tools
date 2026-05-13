# frozen_string_literal: true

require "json"
require "optparse"

module EmTools
  module Plugins
    module AmazonUploadable
      module Cli
        # Ruby port of em-celery +amz_uploadable_products_formatter_from_file.py+ (+filter_products+).
        class AmzUploadableProductsFormatterFromFile
          def run(argv)
            options = {
              store_code: nil,
              marketplace: "us",
              output_path: nil,
              source: nil,
              source_code: nil,
              export: false,
              ttl: 30,
              product_index: nil,
              offer_index: nil,
              emitter_dir: nil,
              skip_offers: false,
              batch_size: 500,
              to_es: false,
              sink_index: nil,
              bulk_chunk: EmTools::Plugins::AmazonUploadable::Formatters::UploadableProductsFormatterFromFile::DEFAULT_SINK_BULK_CHUNK_LINES,
              refresh: false,
              dry_run: false,
            }

            # -- Click-parity CLI options
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools amz-uploadable:format-from-file [options] PRODUCTS_PATH

                Ruby port of +em_celery/tools/spree/amz_uploadable_products_formatter_from_file.py+ (+filter_products+).
                Reads ASINs (one per line), loads product + offer docs from Elasticsearch (+mget+), and outputs
                each formatted row as NDJSON to -o, and/or bulk-indexes the same row into Elasticsearch with
                --to-es (defaults to amz_uploadable_products_<mp>; override with --sink-index). At least one of
                -o or --to-es must be set.

                Set ELASTICSEARCH_URL. Offer index defaults to +lowest_offer_listings_<mp>_new+; use --skip-offers
                to take price/currency from the product document instead.

                Python uses -so / -sc; Ruby OptionParser reserves -s for --store-code, so use --so / --sc here.

                Examples:
                  em-tools amz-uploadable:format-from-file -s MYSTORE -m us -o out.ndjson \\
                    --so AMZ_US --sc wholesale products.txt
                  em-tools amz-uploadable:format-from-file -s MYSTORE -m de --to-es \\
                    --so SRC --sc CODE --skip-offers asins.txt
                  em-tools amz-uploadable:format-from-file -s MYSTORE -m de -o out.ndjson --to-es \\
                    --sink-index amz_uploadable_products_de --bulk-chunk 1000 --refresh \\
                    --so SRC --sc CODE asins.txt
              BANNER

              opts.on("-s", "--store-code CODE", String, "Store code (required; same as Python -s).") do |v|
                options[:store_code] = v
              end
              opts.on("-m", "--marketplace CODE", String, "Amazon marketplace (default us).") do |v|
                options[:marketplace] = v
              end
              opts.on(
                "-o",
                "--output PATH",
                String,
                "Output NDJSON path (required unless --to-es; same as Python -o).",
              ) do |v|
                options[:output_path] = v
              end
              opts.on("--so", "--source NAME", String, "Product source (required; Python -so).") do |v|
                options[:source] = v
              end
              opts.on("--sc", "--source-code CODE", String, "Product source code (required; Python -sc).") do |v|
                options[:source_code] = v
              end
              opts.on("-e", "--export", "Whether to export products to other countries (Python -e).") do
                options[:export] = true
              end
              opts.on("-t", "--ttl N", Integer, "Offer TTL days (default 30; informational).") do |v|
                options[:ttl] = v
              end
              opts.on(
                "--product-index NAME",
                String,
                "Override product ES index (default amz_products_api_<mp>_v2).",
              ) do |v|
                options[:product_index] = v
              end
              opts.on(
                "--offer-index NAME",
                String,
                "Override offer ES index (default lowest_offer_listings_<mp>_new).",
              ) do |v|
                options[:offer_index] = v
              end
              opts.on("--emitter-dir DIR", String, "Sidecar stats directory (default ~/.em_tasks/amz_<mp>).") do |v|
                options[:emitter_dir] = v
              end
              opts.on("--skip-offers", "Do not mget offer index; use price/currency from product _source.") do
                options[:skip_offers] = true
              end
              opts.on("--batch-size N", Integer, "ASINs per mget batch (default 500).") do |v|
                options[:batch_size] = v
              end
              opts.on("--to-es", "Bulk-index formatted rows into Elasticsearch (in addition to or instead of -o).") do
                options[:to_es] = true
              end
              opts.on(
                "--sink-index NAME",
                String,
                "Destination ES index for --to-es (default amz_uploadable_products_<mp>).",
              ) do |v|
                options[:sink_index] = v
                options[:to_es] = true
              end
              opts.on("--bulk-chunk N", Integer, "Documents per bulk request (default 500).") do |v|
                options[:bulk_chunk] = v
              end
              opts.on("--refresh", "Refresh sink index after run (--to-es only).") { options[:refresh] = true }
              opts.on("--dry-run", "Resolve and process but skip ES bulk writes (file output still written).") do
                options[:dry_run] = true
              end
            end
            # rubocop:enable Metrics/BlockLength

            parser.parse!(argv)
            products_path = argv.shift
            if products_path.nil? || argv.any?
              got = ([products_path] + argv).compact.join(" ")
              warn("error: expected exactly one argument (products_path); got: #{got}")
              usage!(parser)
            end

            validate!(options)

            Support.require_elasticsearch_url!

            sink_index = resolved_sink_index(options)
            plugin = EmTools::Core::PluginRegistry.fetch(:amazon_uploadable)
            formatter = plugin.products_formatter(
              marketplace: options[:marketplace],
              products_path: products_path,
              output_path: options[:output_path],
              source: options[:source],
              source_code: options[:source_code],
              store_code: options[:store_code],
              export: options[:export],
              ttl: options[:ttl],
              product_index: options[:product_index],
              offer_index: options[:offer_index],
              emitter_dir: options[:emitter_dir],
              batch_size: options[:batch_size],
              skip_offers: options[:skip_offers],
              sink_index: sink_index,
              sink_bulk_chunk_lines: options[:bulk_chunk],
              sink_refresh: options[:refresh],
              dry_run: options[:dry_run],
            )

            formatter.run!(client: plugin.dependencies[:es_client])
            warn(JSON.generate(
              sink_index: formatter.sink_index,
              output_path: formatter.output_path,
              record: formatter.record,
            ))
          end

          private

          def resolved_sink_index(options)
            return unless options[:to_es]

            explicit = options[:sink_index].to_s.strip
            return explicit unless explicit.empty?

            "amz_uploadable_products_#{options[:marketplace]}"
          end

          def validate!(options)
            missing = []
            missing << "-s / --store-code" if options[:store_code].to_s.strip.empty?
            missing << "--so / --source" if options[:source].to_s.strip.empty?
            missing << "--sc / --source-code" if options[:source_code].to_s.strip.empty?
            if options[:output_path].to_s.strip.empty? && !options[:to_es]
              missing << "-o / --output (or --to-es / --sink-index)"
            end
            return if missing.empty?

            warn("error: missing required option(s): #{missing.join(", ")}")
            exit(1)
          end

          def usage!(parser)
            warn(parser.help)
            exit(1)
          end
        end
      end
    end
  end
end
