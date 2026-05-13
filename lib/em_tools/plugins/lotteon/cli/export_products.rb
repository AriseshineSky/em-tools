# frozen_string_literal: true

module EmTools
  module Plugins
    module Lotteon
      module Cli
        class ExportProducts < EmTools::Core::Plugin::Cli::Base
          def banner
            <<~BANNER
              Usage: em-tools lotteon:export-products [options]

              Stream Lotteon products from Elasticsearch and write them as NDJSON.
              Defaults to the configured Lotteon exporter cluster and index.
            BANNER
          end

          def defaults
            {
              output_path: nil,
              batch_size: 1000,
            }
          end

          def configure(opts, options)
            opts.on("-o", "--output PATH", String, "Write NDJSON to file instead of stdout.") do |value|
              options[:output_path] = value
            end
            opts.on("-b", "--batch-size N", Integer, "Documents per request (default: 1000).") do |value|
              options[:batch_size] = value
            end
          end

          def execute!(options, _argv)
            exporter = EmTools::Plugins::Lotteon::Exporters::ProductsExporter.new
            if options[:output_path]
              exporter.to_jsonl(options[:output_path], batch_size: options[:batch_size])
            else
              exporter.write_jsonl($stdout, batch_size: options[:batch_size])
            end
          end
        end
      end
    end
  end
end
