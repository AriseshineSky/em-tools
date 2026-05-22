# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Ebay
      module Cli
        # +em-tools ebay products export-nonexistent-product-ids+ — write +product_id+ where +existence=false+.
        class ExportNonexistentProductIds < Dry::CLI::Command
          desc "Export product_id values where existence=false"

          option :output,
            aliases: ["-o"],
            required: true,
            desc: "Local output file (one product_id per line)"
          option :index,
            default: "user1_ebay_products",
            desc: "Elasticsearch index (default user1_ebay_products)"
          option :url,
            aliases: ["-u"],
            desc: "Elasticsearch URL override"
          option :cluster,
            desc: "Named ES cluster (e.g. data) instead of --url"
          option :id_field,
            default: "product_id",
            desc: "Id field to export (default product_id)"

          example [
            "-o tmp/ebay_nonexistent_product_ids.txt",
            "-o tmp/out.txt --cluster data",
          ]

          def call(output:, index: "user1_ebay_products", url: nil, cluster: nil,
            id_field: "product_id", **)
            EmTools::Core::Cli::Runner.run do
              es = EmTools::Core::Config.elasticsearch_client(url: url, cluster: cluster)
              summary = Products::NonexistentProductIdsExporter.new(
                es_client: es,
                index: index,
                id_field: id_field,
              ).export!(output)

              EmTools::Core::Cli::Runner::Result.new(
                summary: "Wrote #{summary[:exported_ids]} product_id values to #{summary[:output_path]}",
              )
            end
          end
        end
      end
    end
  end
end
