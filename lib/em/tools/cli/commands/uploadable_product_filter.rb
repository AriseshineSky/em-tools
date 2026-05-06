# frozen_string_literal: true

require 'json'
require 'optparse'

module Em
  module Tools
    module Cli
      module Commands
        class UploadableProductFilter
          def run(argv)
            options = {
              marketplace: 'us',
              index: nil,
              ttl: 30,
              asin_since_days: 7,
              asin_time_field: nil,
              asin_cutoff: nil,
              asin_label: nil,
              asin_label_field: nil,
              config_path: nil,
              dry_run: false,
              max_asins: nil
            }

            # rubocop:disable Metrics/BlockLength -- mirrors many Python CLI flags
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools uploadable-product-filter [options]

                Phase-1 Ruby port of: python -m em_tasks.applications.tools.amazon.uploadable_product_filter
                Streams ASINs from amz_asins_<marketplace> using time range + optional label (see em-tasks asin_stream_options).

                Set ELASTICSEARCH_URL. Optional YAML config (--config) with keys like amz.uploadable_filter.asin_stream.

                Examples:
                  em-tools uploadable-product-filter -m de --asin-since-days 1
                  em-tools uploadable-product-filter -m de --dry-run
                  em-tools uploadable-product-filter -m de \\
                    --config examples/config/amz_uploadable_filter.example.yml --max-asins 100
              BANNER

              opts.on('-m', '--marketplace CODE', String, 'Amazon marketplace (default us).') do |v|
                options[:marketplace] = v
              end
              opts.on('-i', '--index NAME', String, 'Override ASIN Elasticsearch index name.') do |v|
                options[:index] = v
              end
              opts.on('-t', '--ttl N', Integer, 'Offer TTL days (informational; default 30).') { |v| options[:ttl] = v }
              opts.on('--asin-since-days N', Integer, 'Relative window when no absolute cutoff (default 7).') do |v|
                options[:asin_since_days] = v
              end
              opts.on('--asin-time-field FIELD', String, 'auto|timestamp|created_at|time') do |v|
                options[:asin_time_field] = v
              end
              opts.on('--asin-cutoff ISO8601', String, 'Absolute cutoff (time_field > cutoff).') do |v|
                options[:asin_cutoff] = v
              end
              opts.on('--asin-label VALUE', String, 'Optional term filter on label field.') do |v|
                options[:asin_label] = v
              end
              opts.on('--asin-label-field FIELD', String, 'ES field for label term (default label).') do |v|
                options[:asin_label_field] = v
              end
              opts.on('--config PATH', String, 'YAML file merged into stream option resolution.') do |v|
                options[:config_path] = v
              end
              opts.on('--dry-run', 'Print resolved stream config as JSON and exit.') { options[:dry_run] = true }
              opts.on('--max-asins N', Integer, 'Stop after N documents (testing).') { |v| options[:max_asins] = v }
            end
            # rubocop:enable Metrics/BlockLength

            parser.parse!(argv)
            unless argv.empty?
              warn "error: unexpected arguments: #{argv.join(' ')}"
              usage!(parser)
            end

            Support.require_elasticsearch_url!

            cfg =
              if options[:config_path]
                Support.load_yaml_file!(options[:config_path])
              else
                {}
              end

            filter_opts = options.slice(
              :marketplace, :index, :ttl, :asin_since_days, :asin_time_field,
              :asin_cutoff, :asin_label, :asin_label_field
            ).merge(config: cfg)
            filter = Em::Tools::Amazon::UploadableProductFilter.new(**filter_opts)

            if options[:dry_run]
              $stdout.puts(JSON.generate(filter.describe))
              return
            end

            client = Em::Clients::ElasticsearchClient.new
            filter.stream_asins!(client: client, max_asins: options[:max_asins])
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
