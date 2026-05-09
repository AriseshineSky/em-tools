# frozen_string_literal: true

require 'json'
require 'optparse'
require 'yaml'

module EmTools
  module Plugins
    module AmazonUploadable
      module Cli
        # Streams ASINs from an ASIN index, mgets product docs, filters, bulk-writes to a sink ES index.
        class AsinProductsToEs
          def run(argv)
            options = {
              marketplace: 'us',
              product_index: nil,
              sink_index: nil,
              config_path: nil,
              min_price: nil,
              max_price: nil,
              require_fields: nil,
              keywords_path: nil,
              title_field: 'title',
              asin_batch_size: 100,
              bulk_chunk: 200,
              dry_run: false,
              max_asin_hits: nil,
              asin_since_days: 7,
              asin_time_field: nil,
              asin_cutoff: nil,
              asin_label: nil,
              asin_label_field: nil
            }

            # rubocop:disable Metrics/BlockLength
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools asin-products-to-es [options]

                Stream ASINs from the ASIN index (same time/label options as uploadable-product-filter),
                load matching documents from the product API index (mget by ASIN _id),
                resolve price from configurable _source paths, apply min/max price, optional title keyword
                blacklist (substring, same spirit as import-products), optional required fields, then bulk-index
                enriched docs into --sink-index (document _id = ASIN).

                Set ELASTICSEARCH_URL. Create sink index beforehand or rely on dynamic mapping.

                Examples:
                  em-tools asin-products-to-es -m de --sink-index amz_enriched_products_de \\
                    --min-price 10 --max-price 500 --dry-run
                  em-tools asin-products-to-es -m de --sink-index amz_enriched_products_de \\
                    --config examples/config/amazon_asin_product_pipeline.example.yml --max-asin-hits 500
              BANNER

              opts.on('-m', '--marketplace CODE', String, 'Marketplace code (default us).') do |v|
                options[:marketplace] = v
              end
              opts.on('--product-index NAME', String, 'Product API index (default amz_products_api_<mp>_v2).') do |v|
                options[:product_index] = v
              end
              opts.on('--sink-index NAME', String, 'Required. Destination index for enriched documents.') do |v|
                options[:sink_index] = v
              end
              opts.on('--config PATH', String,
                      'Optional YAML merged into ASIN stream resolution (asin_stream block).') do |v|
                options[:config_path] = v
              end
              opts.on('--min-price N', Float, 'Minimum numeric price after resolution (optional).') do |v|
                options[:min_price] = v
              end
              opts.on('--max-price N', Float, 'Maximum numeric price (optional).') do |v|
                options[:max_price] = v
              end
              opts.on('--require-fields CSV', String,
                      'Comma-separated product _source fields that must be non-empty.') do |v|
                options[:require_fields] = v
              end
              opts.on('--keywords-path PATH', String, 'Optional blacklist keywords (title substring match).') do |v|
                options[:keywords_path] = v
              end
              opts.on('--title-field NAME', String, 'Product field for blacklist scan (default title).') do |v|
                options[:title_field] = v
              end
              opts.on('--asin-batch-size N', Integer, 'ASINs per mget batch (default 100).') do |v|
                options[:asin_batch_size] = v
              end
              opts.on('--bulk-chunk N', Integer, 'Documents per bulk request (default 200).') do |v|
                options[:bulk_chunk] = v
              end
              opts.on('--dry-run', 'Resolve and filter but do not call bulk index.') { options[:dry_run] = true }
              opts.on('--max-asin-hits N', Integer, 'Stop after N ASIN index hits (testing).') do |v|
                options[:max_asin_hits] = v
              end
              opts.on('--asin-since-days N', Integer, 'ASIN stream relative window (default 7).') do |v|
                options[:asin_since_days] = v
              end
              opts.on('--asin-time-field FIELD', String) { |v| options[:asin_time_field] = v }
              opts.on('--asin-cutoff ISO8601', String) { |v| options[:asin_cutoff] = v }
              opts.on('--asin-label VALUE', String) { |v| options[:asin_label] = v }
              opts.on('--asin-label-field FIELD', String) { |v| options[:asin_label_field] = v }
            end
            # rubocop:enable Metrics/BlockLength

            parser.parse!(argv)
            unless argv.empty?
              warn "error: unexpected arguments: #{argv.join(' ')}"
              usage!(parser)
            end

            if options[:sink_index].to_s.strip.empty?
              warn 'error: --sink-index is required'
              usage!(parser)
            end

            Support.require_elasticsearch_url!

            cfg =
              if options[:config_path]
                Support.load_yaml_file!(options[:config_path])
              else
                {}
              end

            filter_opts = {
              marketplace: options[:marketplace],
              config: cfg,
              asin_since_days: options[:asin_since_days],
              asin_time_field: options[:asin_time_field],
              asin_cutoff: options[:asin_cutoff],
              asin_label: options[:asin_label],
              asin_label_field: options[:asin_label_field]
            }
            filter = EmTools::Plugins::AmazonUploadable::Filters::UploadableProductFilter.new(**filter_opts)

            keywords = options[:keywords_path] ? Support.load_keywords(options[:keywords_path]) : []
            req = options[:require_fields].to_s.split(',').map(&:strip).reject(&:empty?)

            pipeline = EmTools::Plugins::AmazonUploadable::Pipelines::AsinProductIndexPipeline.new(
              marketplace: options[:marketplace],
              sink_index: options[:sink_index],
              product_index: options[:product_index],
              filter: filter,
              min_price: options[:min_price],
              max_price: options[:max_price],
              require_product_fields: req,
              keywords: keywords,
              title_field: options[:title_field],
              asin_batch_size: options[:asin_batch_size],
              bulk_chunk_lines: options[:bulk_chunk],
              max_asin_hits: options[:max_asin_hits]
            )

            client = EmTools::Clients::ElasticsearchClient.new
            stats = pipeline.run!(client: client, dry_run: options[:dry_run])

            $stdout.puts(JSON.generate(stats.to_h))
          end

          private

          def usage!(parser)
            warn parser.help
            exit 1
          end
        end
      end
    end
  end
end
