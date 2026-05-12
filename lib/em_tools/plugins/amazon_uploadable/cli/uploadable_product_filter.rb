# frozen_string_literal: true

require "json"
require "optparse"

module EmTools
  module Plugins
    module AmazonUploadable
      module Cli
        class UploadableProductFilter
          def run(argv)
            options = {
              marketplace: "us",
              ttl: 30,
              asin_since_days: 7,
              asin_time_field: nil,
              asin_cutoff: nil,
              asin_label: nil,
              asin_label_field: nil,
              config_path: nil,
              dry_run: false,
              max_asins: nil,
              to_es: false,
              sink_index: nil,
              bulk_chunk: EmTools::Plugins::AmazonUploadable::Filters::UploadableProductFilter::DEFAULT_BULK_CHUNK_LINES,
              refresh: false,
            }

            # -- mirrors many Python CLI flags
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools amz-uploadable:filter [options]

                Phase-1 Ruby port of: python -m em_tasks.applications.tools.amazon.uploadable_product_filter
                Streams ASINs from amz_asins_<marketplace> using time range + optional label (see em-tasks asin_stream_options).

                Output: STDOUT (one ASIN per line) by default, or bulk-index into Elasticsearch with --to-es.

                Set ELASTICSEARCH_URL. Optional YAML config (--config) with keys like amz.uploadable_filter.asin_stream.

                Examples:
                  em-tools amz-uploadable:filter -m de --asin-since-days 1
                  em-tools amz-uploadable:filter -m de --dry-run
                  em-tools amz-uploadable:filter -m de --to-es
                  em-tools amz-uploadable:filter -m de --to-es \\
                    --sink-index amz_uploadable_asins_de --bulk-chunk 1000 --refresh
              BANNER

              opts.on("-m", "--marketplace CODE", String, "Amazon marketplace (default us).") do |v|
                options[:marketplace] = v
              end
              opts.on("-t", "--ttl N", Integer, "Offer TTL days (informational; default 30).") { |v| options[:ttl] = v }
              opts.on("--asin-since-days N", Integer, "Relative window when no absolute cutoff (default 7).") do |v|
                options[:asin_since_days] = v
              end
              opts.on("--asin-time-field FIELD", String, "auto|timestamp|created_at|time") do |v|
                options[:asin_time_field] = v
              end
              opts.on("--asin-cutoff ISO8601", String, "Absolute cutoff (time_field > cutoff).") do |v|
                options[:asin_cutoff] = v
              end
              opts.on("--asin-label VALUE", String, "Optional term filter on label field.") do |v|
                options[:asin_label] = v
              end
              opts.on("--asin-label-field FIELD", String, "ES field for label term (default label).") do |v|
                options[:asin_label_field] = v
              end
              opts.on("--config PATH", String, "YAML file merged into stream option resolution.") do |v|
                options[:config_path] = v
              end
              opts.on("--dry-run", "Skip side effects: stdout mode prints resolved config; --to-es skips bulk.") do
                options[:dry_run] = true
              end
              opts.on("--max-asins N", Integer, "Stop after N documents (testing).") { |v| options[:max_asins] = v }
              opts.on("--to-es", "Write matched ASINs into Elasticsearch instead of stdout.") do
                options[:to_es] = true
              end
              opts.on(
                "--sink-index NAME",
                String,
                "Destination ES index for --to-es (default amz_uploadable_asins_<mp>).",
              ) do |v|
                options[:sink_index] = v
              end
              opts.on("--bulk-chunk N", Integer, "Documents per bulk request (default 500).") do |v|
                options[:bulk_chunk] = v
              end
              opts.on("--refresh", "Refresh sink index after run (--to-es only).") { options[:refresh] = true }
            end
            # rubocop:enable Metrics/BlockLength

            parser.parse!(argv)
            unless argv.empty?
              warn("error: unexpected arguments: #{argv.join(" ")}")
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
              :marketplace,
              :ttl,
              :asin_since_days,
              :asin_time_field,
              :asin_cutoff,
              :asin_label,
              :asin_label_field,
            ).merge(config: cfg)
            filter = EmTools::Plugins::AmazonUploadable::Filters::UploadableProductFilter.new(**filter_opts)

            if options[:dry_run] && !options[:to_es]
              $stdout.puts(JSON.generate(filter.describe))
              return
            end

            client = EmTools::Clients::ElasticsearchClient.new

            if options[:to_es]
              stats = filter.bulk_index_asins!(
                client: client,
                sink_index: options[:sink_index],
                max_asins: options[:max_asins],
                bulk_chunk_lines: options[:bulk_chunk],
                dry_run: options[:dry_run],
                refresh: options[:refresh],
              )
              resolved_sink = options[:sink_index].to_s.strip
              resolved_sink = filter.default_sink_index if resolved_sink.empty?
              warn(JSON.generate(sink_index: resolved_sink, stats: stats.to_h, dry_run: options[:dry_run]))
              return
            end

            filter.stream_asins!(client: client, max_asins: options[:max_asins])
          end

          private

          def usage!(parser)
            warn(parser.help)
            exit(1)
          end
        end
      end
    end
  end
end
