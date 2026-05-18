# frozen_string_literal: true

require "csv"
require "json"

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Exporters
          # Exports +top_category+ (or first +categories[]+ name) → document counts from
          # +amz_products_api_<mp>_v2+. Tries ES terms / runtime aggregation first, then scans.
          class TopCategoryStatsExporter
            MISSING_LABEL = "(missing top_category)"
            TERMS_SIZE = 65_535
            SCAN_PROGRESS_EVERY = 500_000

            def initialize(es_client:, product_index:, category_from: :top_category, logger: nil)
              @es = es_client
              @product_index = product_index.to_s.strip
              @category_from = category_from
              @logger = logger || EmTools::Core::Logger.for(progname: "amazon-products")
            end

            # @param output_path [String] TSV path (top_category, doc_count) + .json summary
            # @param query [Hash] ES query filter (without wrapping +query+ key)
            # @return [Hash] summary
            def export!(output_path:, query: nil)
              raise ArgumentError, "product_index is required" if @product_index.empty?

              unless @es.index_exists?(@product_index)
                raise EmTools::Core::Errors::ConfigurationError,
                  "Elasticsearch index not found: #{@product_index}"
              end

              rows, method = collect_counts(query)
              path = File.expand_path(output_path)
              write_tsv(path, rows)
              write_json(path, rows, method)

              total = rows.sum { |r| r[:doc_count] }
              summary = {
                product_index: @product_index,
                output_path: path,
                method: method,
                categories: rows.size,
                documents: total,
              }
              @logger.info { summary.map { |k, v| "#{k}=#{v}" }.join(" ") }
              summary
            end

            def self.index_for_marketplace(marketplace)
              TopCategoryAsinExporter.index_for_marketplace(marketplace)
            end

            private

            def collect_counts(query)
              q = query || { match_all: {} }

              rows = try_runtime_terms_agg(q)
              return [rows, "runtime_field"] if rows_usable?(rows)

              %w[top_category.keyword top_category categories.cat_name.keyword categories.cat_name].each do |field|
                rows = try_terms_agg(q, field)
                return [rows, "terms:#{field}"] if rows_usable?(rows)
              end

              @logger.info { "aggregation did not yield categories; scanning index (may take several minutes)" }
              [scan_counts(q), "scan"]
            end

            def rows_usable?(rows)
              return false if rows.nil? || rows.empty?

              return false if rows.size == 1 && rows.first[:top_category] == MISSING_LABEL

              true
            end

            def try_terms_agg(query, field)
              body = {
                size: 0,
                query: query,
                aggs: {
                  by_top_category: {
                    terms: {
                      field: field,
                      size: TERMS_SIZE,
                      missing: MISSING_LABEL,
                      order: { _count: "desc" },
                    },
                  },
                },
              }
              resp = @es.search(index: @product_index, body: body)
              buckets = resp.dig("aggregations", "by_top_category", "buckets") || []
              buckets.map { |b| { top_category: b["key"].to_s, doc_count: b["doc_count"].to_i } }
            rescue StandardError => e
              @logger.debug { "terms agg failed on #{field}: #{e.message}" }
              nil
            end

            def try_runtime_terms_agg(query)
              body = {
                size: 0,
                query: query,
                runtime_mappings: {
                  first_top_category: {
                    type: "keyword",
                    script: {
                      lang: "painless",
                      source: runtime_script_source,
                    },
                  },
                },
                aggs: {
                  by_top_category: {
                    terms: {
                      field: "first_top_category",
                      size: TERMS_SIZE,
                      missing: MISSING_LABEL,
                      order: { _count: "desc" },
                    },
                  },
                },
              }
              resp = @es.search(index: @product_index, body: body)
              buckets = resp.dig("aggregations", "by_top_category", "buckets") || []
              buckets.map { |b| { top_category: b["key"].to_s, doc_count: b["doc_count"].to_i } }
            rescue StandardError => e
              @logger.debug { "runtime terms agg failed: #{e.message}" }
              nil
            end

            def runtime_script_source
              if @category_from == :categories_first
                <<~PAINLESS.squish
                  if (params._source.categories != null && params._source.categories.length > 0
                      && params._source.categories[0].cat_name != null) {
                    emit(params._source.categories[0].cat_name);
                  } else if (params._source.top_category != null) {
                    emit(params._source.top_category);
                  }
                PAINLESS
              else
                <<~PAINLESS.squish
                  if (params._source.top_category != null) {
                    emit(params._source.top_category);
                  } else if (params._source.categories != null && params._source.categories.length > 0
                      && params._source.categories[0].cat_name != null) {
                    emit(params._source.categories[0].cat_name);
                  }
                PAINLESS
              end
            end

            def scan_counts(query)
              counts = Hash.new(0)
              scanned = 0
              @es.iterate_query(index: @product_index, query: query, batch_size: 2_000) do |hit|
                scanned += 1
                cat = TopCategoryExtract.resolve(hit["_source"], category_from: @category_from)
                counts[cat] += 1
                if (scanned % SCAN_PROGRESS_EVERY).zero?
                  @logger.info { "scan progress: #{scanned} docs, #{counts.size} categories so far" }
                end
              end
              counts.map { |cat, n| { top_category: cat, doc_count: n } }
                .sort_by { |r| [-r[:doc_count], r[:top_category]] }
            end

            def write_tsv(path, rows)
              CSV.open(path, "wb", col_sep: "\t", force_quotes: false) do |csv|
                csv << %w[top_category doc_count]
                rows.each { |r| csv << [r[:top_category], r[:doc_count]] }
              end
            end

            def write_json(path, rows, method)
              json_path = path.sub(/\.[^.]+\z/, "") + ".json"
              payload = {
                "product_index" => @product_index,
                "method" => method,
                "categories" => rows.size,
                "documents" => rows.sum { |r| r[:doc_count] },
                "rows" => rows.map { |r| { "top_category" => r[:top_category], "doc_count" => r[:doc_count] } },
              }
              File.write(json_path, JSON.pretty_generate(payload))
            end
          end
        end
      end
    end
  end
end
