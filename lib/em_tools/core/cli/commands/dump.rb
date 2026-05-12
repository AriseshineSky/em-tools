# frozen_string_literal: true

require "json"
require "optparse"

module EmTools
  module Core
    module Cli
      module Commands
        # Stream every document from an Elasticsearch index as NDJSON to stdout or a file.
        # Cluster selection (explicit URL, primary, or data cluster) is delegated to
        # {EmTools::Core::Config.elasticsearch_client}.
        class Dump
          def run(argv)
            options = { output_path: nil, batch_size: 1000, elasticsearch_url: nil, use_data_cluster: false }

            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools dump INDEX [options]

                Stream all documents from an Elasticsearch index as NDJSON (one hit JSON object per line).

                Primary cluster: ELASTICSEARCH_URL plus optional ELASTICSEARCH_USERNAME /
                ELASTICSEARCH_PASSWORD or ELASTICSEARCH_API_KEY.

                Second cluster (Lotteon / analytics): DATA_ELASTICSEARCH_URL (may include user:pass in URL).
                Use --data to target that cluster when set; or pass -u/--url explicitly.

                Examples:
                  em-tools dump ssg_products > ssg_products.ndjson
                  em-tools dump user1_lotteon_products --data -o tmp/lotteon.ndjson
                  em-tools dump user1_lotteon_products -u 'http://user:pass@host:9200'
              BANNER

              opts.on("-o", "--output PATH", "Write to file instead of stdout") { |path| options[:output_path] = path }
              opts.on("-b", "--batch-size N", Integer, "Documents per request (default: 1000)") do |n|
                options[:batch_size] = n
              end
              opts.on("-u", "--url URL", "Elasticsearch base URL (overrides ELASTICSEARCH_URL for this run)") do |u|
                options[:elasticsearch_url] = u
              end
              opts.on("--data", "Use DATA_ELASTICSEARCH_URL when set (falls back to ELASTICSEARCH_URL)") do
                options[:use_data_cluster] = true
              end
            end

            parser.parse!(argv)
            index = argv.shift
            usage!(parser) unless index && !index.start_with?("-")

            unless argv.empty?
              warn("error: unexpected arguments: #{argv.join(" ")}")
              usage!(parser)
            end

            client = EmTools::Core::Config.elasticsearch_client(
              url: options[:elasticsearch_url],
              prefer_data_cluster: options[:use_data_cluster],
            )
            stream!(client, index, options)
          end

          private

          def stream!(client, index, options)
            out = options[:output_path] ? File.open(options[:output_path], "w") : $stdout
            client.iterate_all(index: index, batch_size: options[:batch_size]) do |hit|
              out.puts(JSON.generate(hit))
            end
          ensure
            out.close if options[:output_path] && out
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
