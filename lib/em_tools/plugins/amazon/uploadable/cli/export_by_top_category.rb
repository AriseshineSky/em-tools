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
            option :marketplaces,
              type: :array,
              desc: "Multiple marketplaces (comma-separated or repeat); writes under <output>/<mp>/"
            option :product_index,
              desc: "Override product ES index"
            option :category_from,
              default: "top_category",
              desc: "top_category (default) or categories_first"
            option :top_category,
              aliases: ["-c"],
              type: :array,
              desc: "Only export these top_category values (repeatable or comma-separated)"
            option :beauty_health,
              type: :boolean,
              default: false,
              desc: "Use marketplace-specific Beauty + Health & Personal Care category names"
            option :url,
              aliases: ["-u"],
              desc: "Elasticsearch base URL override"

            example [
              "-o tmp/amz_de_by_top_category -m de",
              '-o tmp/out -c Beauty -c "Health & Personal Care"',
              "-o tmp/amz_beauty_health --marketplaces uk,ca,jp,mx,ae,in,it,fr --beauty-health",
              "-o tmp/out --product-index amz_products_api_de_v2 --category-from categories_first",
            ]

            def call(output:, marketplace: "de", marketplaces: nil, product_index: nil,
              category_from: "top_category", top_category: nil, beauty_health: false, url: nil, **)
              EmTools::Core::Cli::Runner.run do
                from = parse_category_from!(category_from)
                es = EmTools::Core::Config.elasticsearch_client(url: url)
                mps = parse_marketplaces!(marketplaces, marketplace)

                summaries = mps.map do |mp|
                  categories = resolve_top_categories!(top_category, beauty_health, mp)
                  index = product_index.to_s.strip
                  index = Exporters::TopCategoryAsinExporter.index_for_marketplace(mp) if index.empty?
                  out_dir = mps.size == 1 ? output : File.join(output, mp)

                  Exporters::TopCategoryAsinExporter.new(
                    es_client: es,
                    product_index: index,
                    output_dir: out_dir,
                    category_from: from,
                    only_categories: categories,
                  ).export!
                end

                total_asins = summaries.sum { |s| s[:asins] }
                EmTools::Core::Cli::Runner::Result.new(
                  summary: "Exported #{total_asins} ASINs across #{summaries.size} marketplace(s) " \
                    "under #{File.expand_path(output)}",
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

            def resolve_top_categories!(top_category, beauty_health, marketplace)
              explicit = parse_top_categories!(top_category)
              return explicit if explicit

              if beauty_health
                return BeautyHealthCategories.for_marketplace(marketplace)
              end

              nil
            end

            def parse_marketplaces!(marketplaces, marketplace)
              list = if marketplaces.nil?
                [marketplace]
              else
                marketplaces.flat_map { |v| v.to_s.split(",") }
              end
              list = list.map { |v| v.to_s.strip.downcase }.reject(&:empty?)
              raise EmTools::Core::Errors::ConfigurationError, "marketplace is required" if list.empty?

              list.uniq
            end
          end
        end
      end
    end
  end
end
