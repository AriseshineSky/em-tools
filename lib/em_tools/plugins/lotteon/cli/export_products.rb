# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Lotteon
      module Cli
        # +em-tools lotteon products export+ — stream Lotteon products from Elasticsearch as NDJSON.
        # Defaults to the configured Lotteon exporter cluster and index.
        class ExportProducts < Dry::CLI::Command
          desc "Stream Lotteon products from Elasticsearch as NDJSON"

          option :output, aliases: ["-o"], desc: "Write NDJSON to file instead of stdout"
          option :batch_size,
            aliases: ["-b"],
            default: "1000",
            desc: "Documents per request (default: 1000)"

          option :translation_index,
            desc: "Elasticsearch translation sidecar index; merge +title_en+ into each row"
          option :translation_es_url,
            desc: "Optional Elasticsearch URL for --translation-index (default: product cluster)"
          option :translation_source_field,
            default: "source",
            desc: "Product field for translation doc id (default: source)"
          option :translation_source_product_id_field,
            default: "source_product_id",
            desc: "Product field for translation doc id (default: source_product_id)"

          example [
            "                                  # NDJSON to stdout",
            "-o lotteon_products.ndjson",
          ]

          def call(output: nil, batch_size: "1000",
            translation_index: nil, translation_es_url: nil,
            translation_source_field: "source", translation_source_product_id_field: "source_product_id", **)
            plugin = EmTools::Core::PluginRegistry.fetch(:lotteon)
            exporter = plugin.products_exporter(
              translation_index: translation_index,
              translation_elasticsearch_url: translation_es_url,
              translation_source_field: translation_source_field,
              translation_source_product_id_field: translation_source_product_id_field,
            )
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
