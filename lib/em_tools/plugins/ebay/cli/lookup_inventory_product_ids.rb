# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Ebay
      module Cli
        # +em-tools ebay inventory lookup-product-ids+ — map local eBay item ids to +product_id+
        # via +source+ + +source_product_id+ (default index +user1_ebay_us_products+ on data cluster).
        class LookupInventoryProductIds < Dry::CLI::Command
          desc "Export product_id for Ebay_US rows matching local source_product_id list"

          option :input,
            aliases: ["-i"],
            required: true,
            desc: "Local file: one eBay item id (source_product_id) per line"
          option :output,
            aliases: ["-o"],
            required: true,
            desc: "Output file: one product_id per matched row"
          option :source,
            aliases: ["-s"],
            default: "Ebay_US",
            desc: "source field value (default Ebay_US)"
          option :index,
            aliases: ["--product-index"],
            default: "user1_ebay_us_products",
            desc: "ES index (default user1_ebay_us_products)"
          option :inventory_index,
            desc: "Alias for --index (deprecated)"
          option :url,
            aliases: ["-u"],
            desc: "Elasticsearch URL override"
          option :cluster,
            default: "data",
            desc: "Named ES cluster (default data → DATA_ELASTICSEARCH_URL)"

          example [
            "-i tmp/ebay_item_ids.txt -o tmp/ebay_us_product_ids.txt",
            "-i tmp/ebay_item_ids.txt -o tmp/out.txt --index user1_ebay_us_products --cluster data",
            "-i tmp/ebay_item_ids.txt -o tmp/out.txt --inventory-index em_inventory --cluster primary",
          ]

          def call(input:, output:, source: "Ebay_US", index: "user1_ebay_us_products",
            inventory_index: nil, url: nil, cluster: "data", **)
            EmTools::Core::Cli::Runner.run do
              es = EmTools::Core::Config.elasticsearch_client(url: url, cluster: cluster)
              resolved_index = inventory_index.to_s.strip
              resolved_index = index if resolved_index.empty?
              summary = Inventory::ProductIdsFromFileExporter.new(
                es_client: es,
                source: source,
                index: resolved_index,
              ).export!(input_path: input, output_path: output)

              EmTools::Core::Cli::Runner::Result.new(
                summary: "Wrote #{summary[:matched_rows]} product_id values " \
                  "(#{summary[:lookup_ids]} input ids, source=#{summary[:source]}) " \
                  "to #{summary[:output_path]}",
              )
            end
          end
        end
      end
    end
  end
end
