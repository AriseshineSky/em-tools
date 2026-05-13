# frozen_string_literal: true

require "optparse"

module EmTools
  module Plugins
    module Lotteon
      module Cli
        class ExportProducts
          def run(argv)
            options = {
              output_path: nil,
              batch_size: 1000,
            }

            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools lotteon:export-products [options]

                Stream Lotteon products from Elasticsearch and write them as NDJSON.
                Defaults to the configured Lotteon exporter cluster and index.
              BANNER

              opts.on("-o", "--output PATH", String, "Write NDJSON to file instead of stdout.") do |value|
                options[:output_path] = value
              end
              opts.on("-b", "--batch-size N", Integer, "Documents per request (default: 1000).") do |value|
                options[:batch_size] = value
              end
            end

            parser.parse!(argv)
            unless argv.empty?
              warn("error: unexpected arguments: #{argv.join(" ")}")
              usage!(parser)
            end

            exporter = EmTools::Plugins::Lotteon::Exporters::ProductsExporter.new
            if options[:output_path]
              exporter.to_jsonl(options[:output_path], batch_size: options[:batch_size])
            else
              exporter.write_jsonl($stdout, batch_size: options[:batch_size])
            end
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
