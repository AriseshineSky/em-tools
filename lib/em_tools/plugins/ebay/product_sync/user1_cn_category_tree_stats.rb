# frozen_string_literal: true

require "csv"
require "fileutils"
require "json"

module EmTools
  module Plugins
    module Ebay
      module ProductSync
        # Counts documents in +user1_cn_products+ (or similar) by the first one or two
        # levels of the +categories+ breadcrumb (+Level1+ or +Level1>Level2+).
        class User1CnCategoryTreeStats
          DEFAULT_INDEX = "user1_cn_products"
          DEFAULT_SOURCE = "inspireuplift"
          DEFAULT_OUTPUT_DIR = "tmp/user1_cn_category_tree_stats"
          DEFAULT_CATEGORY_FIELD = "categories"
          SCAN_PROGRESS_EVERY = 50_000

          Stats = Struct.new(
            :index,
            :source_filter,
            :total_docs,
            :level1_categories,
            :level2_categories,
            :method,
            :output_dir,
            keyword_init: true,
          )

          def initialize(
            es_client:,
            index: DEFAULT_INDEX,
            source: DEFAULT_SOURCE,
            category_field: DEFAULT_CATEGORY_FIELD,
            logger: nil
          )
            @es = es_client
            @index = index.to_s.strip
            @source = source.to_s.strip
            @category_field = category_field.to_s.strip
            @logger = logger || EmTools::Core::Logger.for(progname: "user1-cn-categories")
          end

          # @param output_dir [String] directory for level1.tsv, level2.tsv, summary.json
          # @return [Stats]
          def export!(output_dir: DEFAULT_OUTPUT_DIR)
            raise ArgumentError, "index is required" if @index.empty?
            unless @es.index_exists?(@index)
              raise EmTools::Core::Errors::ConfigurationError, "Elasticsearch index not found: #{@index}"
            end

            query = build_query
            total = count_docs(query)
            level1_rows, level2_rows, method = collect_counts(query)

            dir = File.expand_path(output_dir)
            FileUtils.mkdir_p(dir)
            write_tsv(File.join(dir, "level1.tsv"), "level1", level1_rows)
            write_tsv(File.join(dir, "level2.tsv"), "level2_path", level2_rows)
            write_summary(dir, total, level1_rows, level2_rows, method)

            stats = Stats.new(
              index: @index,
              source_filter: @source,
              total_docs: total,
              level1_categories: level1_rows.size,
              level2_categories: level2_rows.size,
              method: method,
              output_dir: dir,
            )
            @logger.info do
              "user1_cn_category_tree index=#{@index} source=#{@source} total=#{total} " \
                "level1=#{stats.level1_categories} level2=#{stats.level2_categories} method=#{method} dir=#{dir}"
            end
            stats
          end

          private

          def build_query
            return { match_all: {} } if @source.empty?

            { term: { "source.keyword" => @source } }
          end

          def count_docs(query)
            resp = @es.search(index: @index, body: { size: 0, track_total_hits: true, query: query })
            raw = resp.dig("hits", "total")
            return raw.to_i if raw.is_a?(Numeric)
            return raw["value"].to_i if raw.is_a?(Hash)

            0
          end

          def collect_counts(query)
            level1 = try_runtime_agg(query, :level1)
            level2 = try_runtime_agg(query, :level2)
            return [level1, level2, "runtime_agg"] if level1.any? && level2.any?

            @logger.info { "runtime aggregation unavailable; scanning index" }
            scan_counts(query)
          end

          def try_runtime_agg(query, level)
            field = runtime_field_name(level)
            body = {
              size: 0,
              query: query,
              runtime_mappings: {
                field => {
                  type: "keyword",
                  script: {
                    lang: "painless",
                    source: runtime_script_source(level),
                  },
                },
              },
              aggs: {
                by_category: {
                  terms: {
                    field: field,
                    size: 65_535,
                    order: { _count: "desc" },
                  },
                },
              },
            }
            resp = @es.search(index: @index, body: body)
            buckets = resp.dig("aggregations", "by_category", "buckets") || []
            buckets.map { |b| { key: b["key"].to_s, doc_count: b["doc_count"].to_i } }
          rescue StandardError => e
            @logger.debug { "runtime agg #{level} failed: #{e.message}" }
            []
          end

          def runtime_field_name(level)
            level == :level1 ? "category_level1" : "category_level2"
          end

          def runtime_script_source(level)
            if level == :level1
              <<~PAINLESS.squish
                def raw = params._source['#{@category_field}'];
                if (raw == null) { emit('#{CategoryPathParser::MISSING_LABEL}'); return; }
                def s = raw.toString();
                int idx = s.indexOf('#{CategoryPathParser::SEPARATOR}');
                if (idx < 0) { emit(s.trim()); return; }
                emit(s.substring(0, idx).trim());
              PAINLESS
            else
              <<~PAINLESS.squish
                def raw = params._source['#{@category_field}'];
                if (raw == null) { emit('#{CategoryPathParser::MISSING_LABEL}'); return; }
                def s = raw.toString().trim();
                if (s.length() == 0) { emit('#{CategoryPathParser::MISSING_LABEL}'); return; }
                def parts = /([^>]+)/.matcher(s);
                def list = new ArrayList();
                while (parts.find()) { list.add(parts.group(1).trim()); }
                if (list.size() == 0) { emit('#{CategoryPathParser::MISSING_LABEL}'); return; }
                if (list.size() == 1) { emit(list.get(0)); return; }
                emit(list.get(0) + '#{CategoryPathParser::SEPARATOR}' + list.get(1));
              PAINLESS
            end
          end

          def scan_counts(query)
            level1_counts = Hash.new(0)
            level2_counts = Hash.new(0)
            scanned = 0

            @es.iterate_query(index: @index, query: query, batch_size: 2_000) do |hit|
              scanned += 1
              parsed = CategoryPathParser.resolve(hit.dig("_source", @category_field))
              level1_counts[parsed[:level1]] += 1
              level2_counts[parsed[:level2_path]] += 1
              if (scanned % SCAN_PROGRESS_EVERY).zero?
                @logger.info { "scan progress: #{scanned} docs" }
              end
            end

            [
              hash_to_rows(level1_counts),
              hash_to_rows(level2_counts),
              "scan",
            ]
          end

          def hash_to_rows(counts)
            counts.map { |key, doc_count| { key: key, doc_count: doc_count } }
              .sort_by { |r| [-r[:doc_count], r[:key]] }
          end

          def write_tsv(path, key_column, rows)
            CSV.open(path, "wb", col_sep: "\t", force_quotes: false) do |csv|
              csv << [key_column, "doc_count"]
              rows.each { |r| csv << [r[:key], r[:doc_count]] }
            end
          end

          def write_summary(dir, total, level1_rows, level2_rows, method)
            payload = {
              "index" => @index,
              "source_filter" => @source,
              "category_field" => @category_field,
              "method" => method,
              "total_docs" => total,
              "level1_sum" => level1_rows.sum { |r| r[:doc_count] },
              "level2_sum" => level2_rows.sum { |r| r[:doc_count] },
              "level1_categories" => level1_rows.size,
              "level2_categories" => level2_rows.size,
              "generated_at" => Time.now.utc.iso8601,
              "level1" => level1_rows.map { |r| { "level1" => r[:key], "doc_count" => r[:doc_count] } },
              "level2" => level2_rows.map { |r| { "level2_path" => r[:key], "doc_count" => r[:doc_count] } },
            }
            File.write(File.join(dir, "summary.json"), JSON.pretty_generate(payload))
          end
        end
      end
    end
  end
end
