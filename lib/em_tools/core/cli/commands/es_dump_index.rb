# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Core
    module Cli
      module Commands
        # +em-tools es dump-index+ — env-driven dump of an ES index to a local NDJSON file.
        # Targets the primary cluster (ELASTICSEARCH_URL).
        class EsDumpIndex < Dry::CLI::Command
          desc "Dump an Elasticsearch index from the primary cluster to NDJSON (env-driven)"

          example [
            "                                  # uses ES_DUMP_INDEX, ES_DUMP_OUTPUT",
          ]

          def call(**)
            EmTools::Core::Cli::Runner.run do
              EmTools::Core::Sinks::IndexDumper.from_env(prefer_data_cluster: false).run!
            end
          end
        end
      end
    end
  end
end
