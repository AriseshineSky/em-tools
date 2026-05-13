# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Ssg
      module Cli
        # +em-tools ssg products export+ — stream SSG products from Elasticsearch as NDJSON.
        class ExportProducts < Dry::CLI::Command
          desc "Stream SSG products from Elasticsearch as NDJSON"

          option :output, aliases: ["-o"], desc: "Write NDJSON to file instead of stdout"
          option :batch_size,
            aliases: ["-b"],
            default: "1000",
            desc: "Documents per request (default: 1000)"

          example [
            "                                  # NDJSON to stdout",
            "-o ssg_products.ndjson -b 2000",
          ]

          def call(output: nil, batch_size: "1000", **)
            plugin = EmTools::Core::PluginRegistry.fetch(:ssg)
            exporter = plugin.products_exporter
            if output
              exporter.to_jsonl(output, batch_size: Integer(batch_size))
            else
              exporter.write_jsonl($stdout, batch_size: Integer(batch_size))
            end
          end
        end
      end
    end
  end
end
