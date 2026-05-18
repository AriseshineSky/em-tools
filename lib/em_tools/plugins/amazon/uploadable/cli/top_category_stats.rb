# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Cli
          # +em-tools amazon products top-category-stats+ — aggregate all +top_category+ values
          # and document counts from +amz_products_api_<mp>_v2+.
          class TopCategoryStats < Dry::CLI::Command
            desc "Export top_category names and document counts (ES terms aggregation)"

            option :output,
              aliases: ["-o"],
              required: true,
              desc: "Output TSV path (also writes .json with the same basename)"
            option :marketplace,
              aliases: ["-m"],
              default: "de",
              desc: "Marketplace code → index amz_products_api_<mp>_v2 (default de)"
            option :product_index,
              desc: "Override product ES index"
            option :category_from,
              default: "top_category",
              desc: "top_category (default) or categories_first"
            option :url,
              aliases: ["-u"],
              desc: "Elasticsearch base URL override"

            example [
              "-o tmp/amz_de_top_category_counts.tsv -m de",
            ]

            def call(output:, marketplace: "de", product_index: nil, category_from: "top_category",
              url: nil, **)
              EmTools::Core::Cli::Runner.run do
                index = product_index.to_s.strip
                index = Exporters::TopCategoryStatsExporter.index_for_marketplace(marketplace) if index.empty?

                from = parse_category_from!(category_from)
                es = EmTools::Core::Config.elasticsearch_client(url: url)
                summary = Exporters::TopCategoryStatsExporter.new(
                  es_client: es,
                  product_index: index,
                  category_from: from,
                ).export!(output_path: output)

                EmTools::Core::Cli::Runner::Result.new(
                  summary: "Wrote #{summary[:categories]} top_category rows " \
                    "(#{summary[:documents]} docs, method=#{summary[:method]}) " \
                    "to #{summary[:output_path]}",
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
