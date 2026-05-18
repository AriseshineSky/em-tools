# frozen_string_literal: true

require "fileutils"
require "json"

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Exporters
          # Scans +amz_products_api_<mp>_v2+ and writes one ASIN-per-line file per +top_category+
          # (or the first +categories[]+ entry when +top_category+ is blank).
          class TopCategoryAsinExporter
            UNCATEGORIZED = "Uncategorized"

            # @param category_from [Symbol] +:top_category+ or +:categories_first+
            # @param only_categories [Array<String>, nil] when set, only write these category names
            def initialize(es_client:, product_index:, output_dir:, category_from: :top_category,
              only_categories: nil, logger: nil)
              @es = es_client
              @product_index = product_index.to_s.strip
              @output_dir = File.expand_path(output_dir)
              @category_from = category_from
              @only_categories = normalize_only_categories(only_categories)
              @logger = logger || EmTools::Core::Logger.for(progname: "amazon-products")
              @counts = Hash.new(0)
            end

            # @param query [Hash] ES query body (+query+ key); default match_all
            # @return [Hash] summary
            def export!(query: nil)
              raise ArgumentError, "product_index is required" if @product_index.empty?

              unless @es.index_exists?(@product_index)
                raise EmTools::Core::Errors::ConfigurationError,
                  "Elasticsearch index not found: #{@product_index}"
              end

              FileUtils.mkdir_p(@output_dir)
              body = query || self.class.query_for_categories(@only_categories) || { match_all: {} }

              @es.iterate_query(
                index: @product_index,
                query: body,
                batch_size: 2_000,
              ) do |hit|
                asin = extract_asin(hit)
                next if asin.empty?

                category = extract_category(hit["_source"])
                next if @only_categories && !@only_categories.include?(category)

                append_asin!(category, asin)
              end

              write_manifest!
              summary = {
                product_index: @product_index,
                output_dir: @output_dir,
                categories: @counts.size,
                asins: @counts.values.sum,
                category_from: @category_from,
              }
              @logger.info { summary.map { |k, v| "#{k}=#{v}" }.join(" ") }
              summary
            end

            def self.index_for_marketplace(marketplace)
              mp = marketplace.to_s.strip.downcase
              raise ArgumentError, "marketplace is required" if mp.empty?

              "amz_products_api_#{mp}_v2"
            end

            def self.query_for_categories(names)
              list = Array(names).map { |n| n.to_s.strip }.reject(&:empty?)
              return if list.empty?
              return { term: { top_category: list.first } } if list.size == 1

              {
                bool: {
                  should: list.map { |cat| { term: { top_category: cat } } },
                  minimum_should_match: 1,
                },
              }
            end

            private

            def normalize_only_categories(names)
              list = Array(names).map { |n| n.to_s.strip }.reject(&:empty?)
              list.empty? ? nil : list
            end

            def extract_asin(hit)
              src = hit["_source"]
              if src.is_a?(Hash)
                a = src["asin"] || src[:asin]
                return a.to_s.strip unless a.to_s.strip.empty?
              end
              hit["_id"].to_s.strip
            end

            def extract_category(source)
              TopCategoryExtract.resolve(source, category_from: @category_from)
            end

            def append_asin!(category, asin)
              path = category_file_path(category)
              File.open(path, "a") { |f| f.puts(asin) }
              @counts[category] += 1
            end

            def category_file_path(category)
              File.join(@output_dir, "#{safe_filename(category)}.txt")
            end

            def safe_filename(name)
              base = name.to_s.strip
              base = UNCATEGORIZED if base.empty?
              base.gsub(/[\/\\:*?"<>|]/, "_").gsub(/\s+/, "_").slice(0, 120)
            end

            def write_manifest!
              manifest = {
                "product_index" => @product_index,
                "category_from" => @category_from.to_s,
                "categories" => @counts.sort_by { |cat, _| cat }.map do |cat, count|
                  { "name" => cat, "count" => count, "file" => File.basename(category_file_path(cat)) }
                end,
              }
              File.write(File.join(@output_dir, "manifest.json"), JSON.pretty_generate(manifest))
            end
          end
        end
      end
    end
  end
end
