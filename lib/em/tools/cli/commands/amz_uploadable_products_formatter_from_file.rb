# frozen_string_literal: true

require 'optparse'

module Em
  module Tools
    module Cli
      module Commands
        # Ruby port of em-celery +amz_uploadable_products_formatter_from_file.py+ (+filter_products+).
        class AmzUploadableProductsFormatterFromFile
          def run(argv)
            options = {
              store_code: nil,
              marketplace: 'us',
              output_path: nil,
              source: nil,
              source_code: nil,
              export: false,
              ttl: 30,
              product_index: nil,
              offer_index: nil,
              emitter_dir: nil,
              skip_offers: false,
              batch_size: 500
            }

            # rubocop:disable Metrics/BlockLength -- Click-parity CLI options
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools amz-uploadable-products-formatter-from-file [options] PRODUCTS_PATH

                Ruby port of +em_celery/tools/spree/amz_uploadable_products_formatter_from_file.py+ (+filter_products+).
                Reads ASINs (one per line), loads product + offer docs from Elasticsearch (+mget+), writes NDJSON.

                Set ELASTICSEARCH_URL. Offer index defaults to +lowest_offer_listings_<mp>_new+; use --skip-offers
                to take price/currency from the product document instead.

                Python uses -so / -sc; Ruby OptionParser reserves -s for --store-code, so use --so / --sc here.

                Examples:
                  em-tools amz-uploadable-products-formatter-from-file -s MYSTORE -m us -o out.ndjson \\
                    --so AMZ_US --sc wholesale products.txt
                  em-tools amz-uploadable-products-formatter-from-file -s MYSTORE -m de -o out.ndjson \\
                    --so SRC --sc CODE --skip-offers asins.txt
              BANNER

              opts.on('-s', '--store-code CODE', String, 'Store code (required; same as Python -s).') do |v|
                options[:store_code] = v
              end
              opts.on('-m', '--marketplace CODE', String, 'Amazon marketplace (default us).') do |v|
                options[:marketplace] = v
              end
              opts.on('-o', '--output PATH', String, 'Output NDJSON path (required; same as Python -o).') do |v|
                options[:output_path] = v
              end
              opts.on('--so', '--source NAME', String, 'Product source (required; Python -so).') do |v|
                options[:source] = v
              end
              opts.on('--sc', '--source-code CODE', String, 'Product source code (required; Python -sc).') do |v|
                options[:source_code] = v
              end
              opts.on('-e', '--export', 'Whether to export products to other countries (Python -e).') do
                options[:export] = true
              end
              opts.on('-t', '--ttl N', Integer, 'Offer TTL days (default 30; informational).') do |v|
                options[:ttl] = v
              end
              opts.on(
                '--product-index NAME', String,
                'Override product ES index (default amz_products_api_<mp>_v2).'
              ) do |v|
                options[:product_index] = v
              end
              opts.on(
                '--offer-index NAME', String,
                'Override offer ES index (default lowest_offer_listings_<mp>_new).'
              ) do |v|
                options[:offer_index] = v
              end
              opts.on('--emitter-dir DIR', String, 'Sidecar stats directory (default ~/.em_tasks/amz_<mp>).') do |v|
                options[:emitter_dir] = v
              end
              opts.on('--skip-offers', 'Do not mget offer index; use price/currency from product _source.') do
                options[:skip_offers] = true
              end
              opts.on('--batch-size N', Integer, 'ASINs per mget batch (default 500).') do |v|
                options[:batch_size] = v
              end
            end
            # rubocop:enable Metrics/BlockLength

            parser.parse!(argv)
            products_path = argv.shift
            if products_path.nil? || argv.any?
              got = ([products_path] + argv).compact.join(' ')
              warn "error: expected exactly one argument (products_path); got: #{got}"
              usage!(parser)
            end

            validate!(options)

            Support.require_elasticsearch_url!

            formatter = Em::Tools::Amazon::UploadableProductsFormatterFromFile.new(
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
              skip_offers: options[:skip_offers]
            )

            client = Em::Clients::ElasticsearchClient.new
            formatter.run!(client: client)
          end

          private

          def validate!(options)
            missing = []
            missing << '-s / --store-code' if options[:store_code].to_s.strip.empty?
            missing << '-o / --output' if options[:output_path].to_s.strip.empty?
            missing << '--so / --source' if options[:source].to_s.strip.empty?
            missing << '--sc / --source-code' if options[:source_code].to_s.strip.empty?
            return if missing.empty?

            warn "error: missing required option(s): #{missing.join(', ')}"
            exit 1
          end

          def usage!(parser)
            warn parser.help
            exit 1
          end
        end
      end
    end
  end
end
