# frozen_string_literal: true

require 'json'
require 'optparse'

module EmTools
  module Plugins
    module AmazonUploadable
      module Cli
        # Ruby counterpart to +em_celery/tools/spree/amz_upload_products_from_es.py+ (+filter_products+).
        class AmzUploadProductsFromEs
          def run(argv)
            options = {
              marketplace: 'us',
              ttl: 30,
              config_path: nil,
              output_path: nil,
              dry_run: false,
              max_asins: nil
            }

            # rubocop:disable Metrics/BlockLength -- Celery-parity CLI options
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools amz-upload-products-from-es [options]

                Ruby port of the Celery/Click command in em-celery +em_celery/tools/spree/amz_upload_products_from_es.py+.
                Same primary flags as Python: -m / -t. Loads optional YAML (price.rules.amz_<mp>, asin stream keys).

                Implemented today: Elasticsearch ASIN stream (same as Python formatter's id stream inputs).
                Not in this gem yet: DB +product_service+, +AmzOfferService+, pipelines, rule engine, file exports.

                Set ELASTICSEARCH_URL.

                Examples:
                  em-tools amz-upload-products-from-es -m de
                  em-tools amz-upload-products-from-es -m de --dry-run
                  em-tools amz-upload-products-from-es -m de -o asins.txt \\
                    --config examples/config/amz_celery_compat.example.yml
              BANNER

              opts.on('-m', '--marketplace CODE', String, 'Amazon marketplace (default us).') do |v|
                options[:marketplace] = v
              end
              opts.on('-t', '--ttl N', Integer, 'Offer TTL days (default 30; informational in Ruby).') do |v|
                options[:ttl] = v
              end
              opts.on('--config PATH', String, 'YAML merged into stream + price rule resolution.') do |v|
                options[:config_path] = v
              end
              opts.on('-o', '--output PATH', String, 'Write ASINs to file instead of stdout.') do |v|
                options[:output_path] = v
              end
              opts.on('--dry-run', 'Print resolved manifest JSON and exit.') { options[:dry_run] = true }
              opts.on('--max-asins N', Integer, 'Stop after N ASINs (testing).') { |v| options[:max_asins] = v }
            end
            # rubocop:enable Metrics/BlockLength

            parser.parse!(argv)
            unless argv.empty?
              warn "error: unexpected arguments: #{argv.join(' ')}"
              usage!(parser)
            end

            cfg =
              if options[:config_path]
                Support.load_yaml_file!(options[:config_path])
              else
                {}
              end

            runner = EmTools::Plugins::AmazonUploadable::Pipelines::UploadProductsFromEs::Runner.new(
              marketplace: options[:marketplace],
              ttl: options[:ttl],
              config: cfg
            )

            if options[:dry_run]
              $stdout.puts(JSON.generate(runner.describe))
              return
            end

            Support.require_elasticsearch_url!

            out = options[:output_path] ? File.open(options[:output_path], 'w') : $stdout
            begin
              client = EmTools::Clients::ElasticsearchClient.new
              runner.run!(client: client, io: out, max_asins: options[:max_asins])
            ensure
              out.close if options[:output_path]
            end
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
