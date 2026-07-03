# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Plugins
    module Ebay
      module ProductSync
        module Cli
          # +em-tools ebay products analyze-user1-cn-categories+ — count +user1_cn_products+
          # docs by the first one or two levels of the +categories+ breadcrumb.
          class AnalyzeUser1CnCategories < Dry::CLI::Command
            desc "Count user1_cn_products docs by categories level1 / level1>level2 (default source inspireuplift)"

            option :url,
              aliases: ["-u", "--source-url"],
              desc: "Elasticsearch URL (default DATA_ELASTICSEARCH_URL)"
            option :index,
              default: User1CnCategoryTreeStats::DEFAULT_INDEX,
              desc: "Source index (default user1_cn_products)"
            option :source,
              aliases: ["-s"],
              default: User1CnCategoryTreeStats::DEFAULT_SOURCE,
              desc: "Filter source.keyword (default inspireuplift; empty for all docs)"
            option :category_field,
              default: User1CnCategoryTreeStats::DEFAULT_CATEGORY_FIELD,
              desc: "Category breadcrumb field (default categories)"
            option :output,
              aliases: ["-o"],
              default: User1CnCategoryTreeStats::DEFAULT_OUTPUT_DIR,
              desc: "Output directory for level1.tsv, level2.tsv, summary.json"

            example [
              "-o tmp/inspireuplift_categories",
              "-s inspireuplift -o tmp/user1_cn_category_tree_stats",
              "-u http://host:9200 --index user1_cn_products",
            ]

            def call(url: nil, index: User1CnCategoryTreeStats::DEFAULT_INDEX,
              source: User1CnCategoryTreeStats::DEFAULT_SOURCE,
              category_field: User1CnCategoryTreeStats::DEFAULT_CATEGORY_FIELD,
              output: User1CnCategoryTreeStats::DEFAULT_OUTPUT_DIR, **)
              EmTools::Core::Cli::Runner.run do
                es_url = resolve_url(url)
                if es_url.empty?
                  raise EmTools::Core::Errors::ConfigurationError,
                    "Elasticsearch URL is required (set DATA_ELASTICSEARCH_URL or pass --url)"
                end

                plugin = EmTools::Core::PluginRegistry.fetch(:ebay)
                stats = User1CnCategoryTreeStats.new(
                  es_client: EmTools::Core::Config.elasticsearch_client(url: es_url),
                  index: index,
                  source: source,
                  category_field: category_field,
                  logger: plugin.dependencies[:logger],
                ).export!(output_dir: output)

                $stdout.puts(JSON.generate(stats.to_h))
                EmTools::Core::Cli::Runner::Result.new(
                  summary: "Wrote category tree stats to #{stats.output_dir} " \
                    "(total=#{stats.total_docs} level1=#{stats.level1_categories} " \
                    "level2=#{stats.level2_categories} method=#{stats.method})",
                )
              end
            end

            private

            def resolve_url(cli_url)
              raw = cli_url.to_s.strip
              return raw unless raw.empty?

              EmTools::Core::Config.data_elasticsearch_url.to_s
            rescue RuntimeError
              ""
            end
          end
        end
      end
    end
  end
end
