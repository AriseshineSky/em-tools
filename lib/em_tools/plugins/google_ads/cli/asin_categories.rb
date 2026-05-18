# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module GoogleAds
      module Cli
        # +em-tools google-ads catalog asin-categories+ — mget ASINs from a local list against
        # +amz_products_api_<mp>_v2+ and write the first +categories[]+ entry per ASIN.
        class AsinCategories < Dry::CLI::Command
          desc "Lookup first-level Amazon categories for ASINs from a local id file (TSV output)"

          option :input,
            aliases: ["-i"],
            required: true,
            desc: "Local ASIN list (e.g. output of catalog missing-product-ids)"
          option :output,
            aliases: ["-o"],
            required: true,
            desc: "Output TSV path (asin, cat_id, cat_name, status)"
          option :marketplace,
            aliases: ["-m"],
            default: "de",
            desc: "Amazon marketplace code for index amz_products_api_<mp>_v2 (default de)"
          option :product_index,
            desc: "Override product ES index (default amz_products_api_<marketplace>_v2)"
          option :url,
            aliases: ["-u"],
            desc: "Elasticsearch base URL override (default ELASTICSEARCH_URL)"

          example [
            "-i tmp/amz_de_missing_from_google_ads.txt -o tmp/amz_de_asin_categories.tsv -m de",
            "-i tmp/ids.txt -o out.tsv --product-index amz_products_api_de_v2",
          ]

          def call(input:, output:, marketplace: "de", product_index: nil, url: nil, **)
            EmTools::Core::Cli::Runner.run do
              index = product_index.to_s.strip
              index = Catalog::AsinCategoryExporter.index_for_marketplace(marketplace) if index.empty?

              es = EmTools::Core::Config.elasticsearch_client(url: url)
              summary = Catalog::AsinCategoryExporter.new(es_client: es, product_index: index).export!(
                input_path: input,
                output_path: output,
              )

              EmTools::Core::Cli::Runner::Result.new(
                summary: "Wrote #{summary[:asins]} ASIN rows " \
                  "(found=#{summary[:found]} missing=#{summary[:missing]} " \
                  "no_category=#{summary[:no_category]}) to #{summary[:output_path]}",
              )
            end
          end
        end
      end
    end
  end
end
