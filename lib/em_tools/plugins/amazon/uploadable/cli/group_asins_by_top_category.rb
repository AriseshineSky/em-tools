# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Cli
          # +em-tools amazon products group-asins-by-top-category+ — mget sold ASINs from a local
          # list against +amz_products_api_<mp>_v2+ and write +marketplace/top_category/asins.txt+.
          class GroupAsinsByTopCategory < Dry::CLI::Command
            desc "Group local ASINs by top_category from amz_products_api_<mp>_v2 (mget by _id)"

            option :output,
              aliases: ["-o"],
              required: true,
              desc: "Output root (writes <mp>/<top_category>/asins.txt)"
            option :input,
              aliases: ["-i"],
              desc: "Single ASIN list file"
            option :input_dir,
              desc: "Directory of AMZ_<MP>.txt files (e.g. tmp/sold_asin); runs one export per file"
            option :marketplace,
              aliases: ["-m"],
              desc: "Marketplace code when using --input (default de)"
            option :product_index,
              desc: "Override product ES index"
            option :category_from,
              default: "top_category",
              desc: "top_category (default) or categories_first"
            option :url,
              aliases: ["-u"],
              desc: "Elasticsearch base URL override"

            example [
              "-i tmp/sold_asin/AMZ_DE.txt -m de -o tmp/sold_asin_by_top_category",
              "--input-dir tmp/sold_asin -o tmp/sold_asin_by_top_category",
              '-u http://34.44.148.50 --input-dir tmp/sold_asin -o tmp/sold_asin_by_top_category',
            ]

            def call(output:, input: nil, input_dir: nil, marketplace: nil, product_index: nil,
              category_from: "top_category", url: nil, **)
              EmTools::Core::Cli::Runner.run do
                from = parse_category_from!(category_from)
                es = EmTools::Core::Config.elasticsearch_client(url: url)
                jobs = build_jobs!(input: input, input_dir: input_dir, marketplace: marketplace)
                summaries = jobs.map do |job|
                  index = product_index.to_s.strip
                  if index.empty?
                    index = Exporters::AsinsByTopCategoryExporter.index_for_marketplace(job[:marketplace])
                  end

                  Exporters::AsinsByTopCategoryExporter.new(
                    es_client: es,
                    product_index: index,
                    output_dir: output,
                    marketplace: job[:marketplace],
                    category_from: from,
                  ).export!(input_path: job[:input_path])
                end

                parts = summaries.map do |s|
                  "#{s[:marketplace]}: #{s[:asins]} ASINs → #{s[:categories]} categories " \
                    "(missing=#{s[:missing]})"
                end
                EmTools::Core::Cli::Runner::Result.new(
                  summary: "Wrote #{summaries.size} marketplace(s) under #{File.expand_path(output)}. " \
                    "#{parts.join("; ")}",
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

            def build_jobs!(input:, input_dir:, marketplace:)
              if input_dir.to_s.strip != ""
                dir = File.expand_path(input_dir)
                raise EmTools::Core::Errors::ConfigurationError, "input_dir not found: #{dir}" unless File.directory?(dir)

                paths = Dir.glob(File.join(dir, "AMZ_*.txt")).sort
                raise EmTools::Core::Errors::ConfigurationError,
                  "no AMZ_*.txt files in #{dir}" if paths.empty?

                return paths.map do |path|
                  {
                    input_path: path,
                    marketplace: Exporters::AsinsByTopCategoryExporter.marketplace_from_sold_filename(path),
                  }
                end
              end

              path = input.to_s.strip
              raise EmTools::Core::Errors::ConfigurationError,
                "provide --input or --input-dir" if path.empty?

              mp = marketplace.to_s.strip.downcase
              mp = "de" if mp.empty?
              [{ input_path: path, marketplace: mp }]
            end
          end
        end
      end
    end
  end
end
