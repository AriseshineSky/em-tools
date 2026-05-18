# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Cli
          # +em-tools amazon products group-inventory-by-top-category+ — scroll +em_inventory+ for a
          # +source+, mget +source_product_id+ in +amz_products_api_<mp>_v2+, write by +top_category+.
          class GroupInventoryByTopCategory < Dry::CLI::Command
            desc "Group em_inventory source_product_id values by top_category (amz_products_api_*_v2)"

            option :output,
              aliases: ["-o"],
              required: true,
              desc: "Output root (writes <mp>/<top_category>/asins.txt)"
            option :source,
              aliases: ["-s"],
              required: true,
              desc: "Inventory source filter (e.g. amz_de → query source:amz_de)"
            option :marketplace,
              aliases: ["-m"],
              desc: "Marketplace code (default: inferred from --source, e.g. amz_de → de)"
            option :inventory_index,
              default: "em_inventory",
              desc: "Inventory ES index (default em_inventory)"
            option :product_index,
              desc: "Override product ES index (default amz_products_api_<marketplace>_v2)"
            option :source_field,
              default: "source",
              desc: "Inventory source field (default source)"
            option :id_field,
              default: "source_product_id",
              desc: "Inventory product id field (default source_product_id)"
            option :category_from,
              default: "top_category",
              desc: "top_category (default) or categories_first"
            option :url,
              aliases: ["-u"],
              desc: "Elasticsearch base URL override"

            example [
              "-s amz_de -o tmp/amz_de_inventory_by_top_category",
              "-s AMZ_DE -m de -o tmp/out --inventory-index em_inventory",
            ]

            def call(output:, source:, marketplace: nil, inventory_index: "em_inventory",
              product_index: nil, source_field: "source", id_field: "source_product_id",
              category_from: "top_category", url: nil, **)
              EmTools::Core::Cli::Runner.run do
                mp = marketplace.to_s.strip.downcase
                mp = Exporters::InventoryAsinsByTopCategoryExporter.marketplace_from_source(source) if mp.empty?
                from = parse_category_from!(category_from)
                es = EmTools::Core::Config.elasticsearch_client(url: url)

                summary = Exporters::InventoryAsinsByTopCategoryExporter.new(
                  es_client: es,
                  source: source,
                  marketplace: mp,
                  output_dir: output,
                  inventory_index: inventory_index,
                  product_index: product_index,
                  source_field: source_field,
                  id_field: id_field,
                  category_from: from,
                ).export!

                EmTools::Core::Cli::Runner::Result.new(
                  summary: "Wrote #{summary[:asins]} ASINs into #{summary[:categories]} categories " \
                    "under #{summary[:output_dir]} (#{summary[:inventory_index]} source=#{summary[:inventory_source]}, " \
                    "missing=#{summary[:missing]})",
                )
              end
            end

            private

            def parse_category_from!(raw)
              case raw.to_s.strip.downcase
              when "top_category", "top" then :top_category
              when "categories_first", "categories", "first" then :categories_first
              else
                raise EmTools::Core::Errors::ConfigurationError,
                  "category_from must be top_category or categories_first, got: #{raw.inspect}"
              end
            end
          end
        end
      end
    end
  end
end
