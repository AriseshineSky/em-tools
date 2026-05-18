# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module GoogleAds
      module Cli
        # +em-tools google-ads catalog missing-product-ids+ — write +source_product_id+ values that
        # exist in +em_inventory+ but not in +google_ads_products+ for a given +source+.
        class MissingProductIds < Dry::CLI::Command
          desc "Export source_product_id values in inventory but missing from the Google Ads catalog index"

          option :source,
            required: true,
            desc: "Source key to match (e.g. AMZ_DE, amz_de)"
          option :output,
            aliases: ["-o"],
            required: true,
            desc: "Local output file path (one id per line after a short header)"
          option :inventory_index,
            default: "em_inventory",
            desc: "Inventory ES index (default em_inventory)"
          option :catalog_index,
            default: "google_ads_products",
            desc: "Google Ads catalog ES index (default google_ads_products)"
          option :url,
            aliases: ["-u"],
            desc: "Elasticsearch base URL override (default ELASTICSEARCH_URL)"
          option :source_field,
            default: "source",
            desc: "Field holding the source key (default source; uses source.keyword when unqualified)"
          option :id_field,
            default: "source_product_id",
            desc: "Product id field to export (default source_product_id)"

          example [
            "--source AMZ_DE -o tmp/amz_de_missing_from_google_ads.txt",
            "--source amz_de -o tmp/missing.txt -u http://localhost:9200",
          ]

          def call(source:, output:, inventory_index: "em_inventory", catalog_index: "google_ads_products",
            url: nil, source_field: "source", id_field: "source_product_id", **)
            EmTools::Core::Cli::Runner.run do
              es = EmTools::Core::Config.elasticsearch_client(url: url)
              summary = Catalog::MissingProductIdsExporter.new(
                es_client: es,
                source: source,
                inventory_index: inventory_index,
                catalog_index: catalog_index,
                source_field: source_field,
                id_field: id_field,
              ).export!(output)

              EmTools::Core::Cli::Runner::Result.new(
                summary: "Wrote #{summary[:missing_ids]} missing #{id_field} " \
                  "(inventory=#{summary[:inventory_ids]} catalog=#{summary[:catalog_ids]}) " \
                  "to #{summary[:output_path]}",
              )
            end
          end
        end
      end
    end
  end
end
