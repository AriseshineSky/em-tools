# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Core
    module Cli
      module Commands
        # +em-tools dump INDEX+ — stream every doc from an Elasticsearch index as NDJSON.
        # Cluster selection (explicit URL / primary / data) is delegated to
        # {EmTools::Core::Config.elasticsearch_client}.
        class Dump < Dry::CLI::Command
          desc "Stream every document from an Elasticsearch index as NDJSON"

          argument :index, required: true, desc: "Elasticsearch index name"

          option :output, aliases: ["-o"], desc: "Write to file instead of stdout"
          option :batch_size, aliases: ["-b"], default: "1000", desc: "Documents per request (default: 1000)"
          option :url, aliases: ["-u"], desc: "Elasticsearch base URL (overrides ELASTICSEARCH_URL for this run)"
          option :data,
            type: :flag,
            default: false,
            desc: "Use DATA_ELASTICSEARCH_URL when set (falls back to ELASTICSEARCH_URL)"

          example [
            "ssg_products > ssg_products.ndjson",
            "user1_lotteon_products --data -o tmp/lotteon.ndjson",
            "user1_lotteon_products -u 'http://user:pass@host:9200'",
          ]

          def call(index:, output: nil, batch_size: "1000", url: nil, data: false, **)
            client = EmTools::Core::Config.elasticsearch_client(
              url: url,
              prefer_data_cluster: data,
            )
            stream!(client, index, output: output, batch_size: Integer(batch_size))
          end

          private

          def stream!(client, index, output:, batch_size:)
            io = output ? File.open(output, "w") : $stdout
            client.iterate_all(index: index, batch_size: batch_size) do |hit|
              io.puts(JSON.generate(hit))
            end
          ensure
            io.close if output && io
          end
        end
      end
    end
  end
end
