# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Cli
          # +em-tools amazon products export-by-top-category+ — scan +amz_products_api_<mp>_v2+ and
          # write one ASIN list file per first-level category (+top_category+ by default).
          class ExportByTopCategory < Dry::CLI::Command
            desc "Export ASINs grouped by top-level category from amz_products_api_*_v2"

            option :output,
              aliases: ["-o"],
              required: true,
              desc: "Output directory (one <category>.txt per top category)"
            option :marketplace,
              aliases: ["-m"],
              default: "de",
              desc: "Marketplace code → index amz_products_api_<mp>_v2 (default de)"
            option :product_index,
              desc: "Override product ES index"
            option :category_from,
              default: "top_category",
              desc: "top_category (default) or categories_first"
            option :top_category,
              aliases: ["-c"],
              type: :array,
              desc: "Only export these top_category values (repeatable or comma-separated)"
            option :url,
              aliases: ["-u"],
              desc: "Elasticsearch base URL override"

            example [
              "-o tmp/amz_de_by_top_category -m de",
              '-o tmp/out -c Beauty -c "Health & Personal Care"',
              "-o tmp/out --product-index amz_products_api_de_v2 --category-from categories_first",
            ]

            def call(output:, marketplace: "de", product_index: nil, category_from: "top_category",
              top_category: nil, url: nil, **)
              EmTools::Core::Cli::Runner.run do
                index = product_index.to_s.strip
                index = Exporters::TopCategoryAsinExporter.index_for_marketplace(marketplace) if index.empty?

                from = parse_category_from!(category_from)
                categories = parse_top_categories!(top_category)
                es = EmTools::Core::Config.elasticsearch_client(url: url)
                summary = Exporters::TopCategoryAsinExporter.new(
                  es_client: es,
                  product_index: index,
                  output_dir: output,
                  category_from: from,
                  only_categories: categories,
                ).export!

                EmTools::Core::Cli::Runner::Result.new(
                  summary: "Exported #{summary[:asins]} ASINs into #{summary[:categories]} files " \
                    "under #{summary[:output_dir]}",
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

            def parse_top_categories!(raw)
              return if raw.nil?

              raw.flat_map { |v| v.to_s.split(",") }.map(&:strip).reject(&:empty?)
            end
          end
        end
      end
    end
  end
end
