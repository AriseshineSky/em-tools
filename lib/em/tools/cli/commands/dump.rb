# frozen_string_literal: true

require 'json'
require 'optparse'

module Em
  module Tools
    module Cli
      module Commands
        class Dump
          def run(argv)
            options = { output_path: nil, batch_size: 1000 }

            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools dump INDEX [options]

                Stream all documents from an Elasticsearch index as NDJSON (one hit JSON object per line).

                Set ELASTICSEARCH_URL (e.g. http://host:9200). Optional: create a .env file when using dotenv.

                Examples:
                  em-tools dump ssg_products > ssg_products.ndjson
                  em-tools dump ssg_products -o ssg_products.ndjson
              BANNER

              opts.on('-o', '--output PATH', 'Write to file instead of stdout') { |path| options[:output_path] = path }
              opts.on('-b', '--batch-size N', Integer, 'Documents per request (default: 1000)') do |n|
                options[:batch_size] = n
              end
            end

            parser.parse!(argv)
            index = argv.shift
            usage!(parser) unless index && !index.start_with?('-')

            unless argv.empty?
              warn "error: unexpected arguments: #{argv.join(' ')}"
              usage!(parser)
            end

            Support.require_elasticsearch_url!

            client = Em::Clients::ElasticsearchClient.new
            out = options[:output_path] ? File.open(options[:output_path], 'w') : $stdout

            begin
              client.iterate_all(index: index, batch_size: options[:batch_size]) do |hit|
                out.puts(JSON.generate(hit))
              end
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
