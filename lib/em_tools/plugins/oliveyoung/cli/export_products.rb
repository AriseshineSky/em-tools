# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Oliveyoung
      module Cli
        # +em-tools oliveyoung products export+ — stream Oliveyoung products
        # (filtered to +source=oliveyoung+) from Elasticsearch as NDJSON.
        class ExportProducts < Dry::CLI::Command
          desc "Stream Oliveyoung products from Elasticsearch as NDJSON"

          option :output, aliases: ["-o"], desc: "Write NDJSON to file instead of stdout"
          option :batch_size,
            aliases: ["-b"],
            default: "1000",
            desc: "Documents per request (default: 1000)"
          option :source,
            aliases: ["-s"],
            desc: "Override source filter value (default: oliveyoung)"

          example [
            "                                  # NDJSON to stdout",
            "-o oliveyoung.ndjson -b 2000",
            "-s OLIVEYOUNG                     # case override",
          ]

          def call(output: nil, batch_size: "1000", source: nil, **)
            plugin = EmTools::Core::PluginRegistry.fetch(:oliveyoung)
            exporter = plugin.products_exporter(source_value: source)
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
