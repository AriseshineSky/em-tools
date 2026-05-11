# frozen_string_literal: true

require "optparse"

module EmTools
  module Core
    module Cli
      module Commands
        # Dump an Elasticsearch index from the read-only data cluster (DATA_ELASTICSEARCH_URL).
        # Convenience wrapper around +es-dump-index+ that flips the cluster default.
        class EsDownloadProduct
          def run(argv)
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools es-download-product

                Dump an index from the data cluster (DATA_ELASTICSEARCH_URL) to a local NDJSON file.
                Env: ES_DUMP_INDEX, ES_DUMP_OUTPUT, ES_DUMP_BATCH_SIZE.
              BANNER
              opts.on_tail("-h", "--help") do
                puts opts
                exit(0)
              end
            end
            parser.parse!(argv)

            unless argv.empty?
              warn("error: unexpected arguments: #{argv.join(" ")}")
              exit(1)
            end

            EmTools::Core::Cli::Runner.run do
              EmTools::Core::Sinks::IndexDumper.from_env(prefer_data_cluster: true).run!
            end
          end
        end
      end
    end
  end
end
