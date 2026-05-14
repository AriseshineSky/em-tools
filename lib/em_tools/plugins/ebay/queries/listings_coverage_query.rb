# frozen_string_literal: true

require "fileutils"
require "json"

module EmTools
  module Plugins
    module Ebay
      module Queries
        # Time-window activity and seed coverage for one configurable eBay products ES index (default
        # +ebay_us_products+). +terms+ field matches +product_id+ (+EBAY_LISTINGS_COVERAGE_ID_FIELD+).
        #
        # Seed list: tab file column-2 JSON +source_product_id+ (same shape as lowest-offer seeds), read from
        # +EBAY_LISTINGS_COVERAGE_SEED_DIR+/+ebay_<mp>.txt+ or +EBAY_LISTINGS_COVERAGE_SEED_FILE+.
        class ListingsCoverageQuery
          TERMS_BATCH_SIZE_MIN = 200
          TERMS_BATCH_SIZE_MAX = 5000
          TERMS_BATCH_SIZE_DEFAULT = 2000

          SOURCE_PRODUCT_ID_JSON_RE = /"source_product_id"\s*:\s*"([^"\\\s]+)"/

          TIME_ACTIVITY_DOC_BUCKET_KEYS = [
            :time_last_24h,
            :time_24_to_48h_ago,
            :time_48_to_72h_ago,
            :time_72_to_96h_ago,
            :time_96_to_120h_ago,
            :time_older_than_120h,
            :time_at_or_after_now,
            :time_other_window,
            :docs_missing_time,
          ].freeze

          def initialize(es_client:, marketplace:, snapshot_time: nil, index_name: nil, time_field: nil, id_field: nil,
            seed_dir: nil, seed_file: nil, seed_text_fetcher: nil, id_source: nil,
            inventory_index: nil, inventory_source_field: nil, inventory_source_terms: nil,
            inventory_product_id_field: nil, inventory_marketplace_field: nil, inventory_max_hits: nil)
            @es_client = es_client
            @marketplace = marketplace.to_s.downcase
            @snapshot_time = snapshot_time&.utc
            idx = (index_name || ENV["EBAY_LISTINGS_COVERAGE_INDEX"]).to_s.strip
            @index_name = idx.empty? ? "ebay_us_products" : idx
            @seed_dir = (seed_dir || ENV["EBAY_LISTINGS_COVERAGE_SEED_DIR"]).to_s.strip
            sf = (seed_file || ENV["EBAY_LISTINGS_COVERAGE_SEED_FILE"]).to_s.strip
            @seed_file = sf.empty? ? nil : File.expand_path(sf)
            @seed_text_fetcher = seed_text_fetcher
            @id_source = (id_source || ENV["EBAY_LISTINGS_COVERAGE_ID_SOURCE"] || "seed").to_s.strip.downcase
            configure_inventory_options!(
              inventory_index: inventory_index,
              inventory_source_field: inventory_source_field,
              inventory_source_terms: inventory_source_terms,
              inventory_product_id_field: inventory_product_id_field,
              inventory_marketplace_field: inventory_marketplace_field,
              inventory_max_hits: inventory_max_hits,
            )
            tf = time_field.to_s.strip
            @time_field = tf.empty? ? ENV.fetch("EBAY_LISTINGS_COVERAGE_TIME_FIELD", "time") : tf
            af = id_field.to_s.strip
            @id_field = af.empty? ? ENV.fetch("EBAY_LISTINGS_COVERAGE_ID_FIELD", "product_id.keyword") : af
            raw_bs = ENV.fetch("EBAY_LISTINGS_COVERAGE_TERMS_BATCH_SIZE", TERMS_BATCH_SIZE_DEFAULT.to_s).to_i
            @terms_batch_size = raw_bs.clamp(TERMS_BATCH_SIZE_MIN, TERMS_BATCH_SIZE_MAX)

            @write_missing_ids = ENV["EBAY_LISTINGS_COVERAGE_WRITE_MISSING_IDS"] != "false"
            dir_raw = ENV["EBAY_LISTINGS_COVERAGE_MISSING_IDS_DIR"].to_s.strip
            @missing_ids_dir =
              if !@write_missing_ids || dir_raw == "-"
                nil
              elsif dir_raw.empty?
                File.expand_path("tmp/ebay_listings_missing_ids", Dir.pwd)
              else
                File.expand_path(dir_raw)
              end
          end

          def fetch_row
            seeds = load_seed_ids
            row = base_row(seeds)
            activity = search_activity(seeds)
            coverage = search_seed_coverage(seeds) if seeds.any?
            row.merge!(activity)
            row.merge!(coverage || empty_coverage)
            row
          rescue StandardError => e
            warn("ListingsCoverageQuery failed for #{@index_name}: #{e.class} #{e.message}")
            seeds = load_seed_ids
            base_row(seeds).merge(empty_activity).merge(empty_coverage).merge(error: e.message.to_s.byteslice(0, 200))
          end

          private

          def configure_inventory_options!(inventory_index:, inventory_source_field:, inventory_source_terms:,
            inventory_product_id_field:, inventory_marketplace_field:, inventory_max_hits:)
            @inventory_index = (inventory_index || ENV["EBAY_LISTINGS_COVERAGE_INVENTORY_INDEX"]).to_s.strip
            @inventory_index = "em_inventory" if @inventory_index.empty?
            sf = (inventory_source_field || ENV["EBAY_LISTINGS_COVERAGE_INVENTORY_SOURCE_FIELD"]).to_s.strip
            @inventory_source_field = sf.empty? ? "source.keyword" : sf
            terms = inventory_source_terms || parse_csv_env("EBAY_LISTINGS_COVERAGE_INVENTORY_SOURCE_TERMS")
            @inventory_source_terms = terms
            pf = (inventory_product_id_field || ENV["EBAY_LISTINGS_COVERAGE_INVENTORY_PRODUCT_ID_FIELD"]).to_s.strip
            @inventory_product_id_field = pf.empty? ? "source_product_id" : pf
            mf = (inventory_marketplace_field || ENV["EBAY_LISTINGS_COVERAGE_INVENTORY_MARKETPLACE_FIELD"]).to_s.strip
            @inventory_marketplace_field = mf.empty? ? nil : mf
            @inventory_max_hits = inventory_max_hits
          end

          def parse_csv_env(key)
            ENV[key].to_s.split(",").map(&:strip).reject(&:empty?)
          end

          def base_row(seeds)
            {
              marketplace: @marketplace.upcase,
              index_name: @index_name,
              id_source: @id_source,
              inventory_index: (@id_source == "inventory" ? @inventory_index : nil),
              seed_ids_loaded: seeds.length,
              seed_ids_unique: seeds.uniq.length,
              seed_file_present: seed_file_present?,
            }
          end

          def seed_file_present?
            return false if @id_source == "inventory"

            return File.file?(@seed_file) if @seed_file

            return false if @seed_dir.empty?

            File.file?(File.join(@seed_dir, "ebay_#{@marketplace}.txt"))
          end

          def load_seed_ids
            return load_ids_from_inventory if @id_source == "inventory"

            text =
              if @seed_file && File.file?(@seed_file)
                File.read(@seed_file, encoding: "UTF-8")
              elsif !@seed_dir.empty?
                read_seed_text_from_dir
              elsif @seed_text_fetcher
                @seed_text_fetcher.call(@marketplace)
              end
            return [] if text.nil? || text.to_s.empty?

            extract_source_product_ids_from_seed_text(text.to_s)
          rescue StandardError => e
            warn("ListingsCoverageQuery seed load failed for #{@marketplace}: #{e.message}")
            []
          end

          def load_ids_from_inventory
            loader = EbayListingsInventoryProductIdLoader.new(
              es_client: @es_client,
              index: @inventory_index,
              source_field: @inventory_source_field,
              source_terms: @inventory_source_terms,
              product_id_field: @inventory_product_id_field,
              marketplace_field: @inventory_marketplace_field,
              max_hits: @inventory_max_hits,
            )
            loader.load(@marketplace)
          rescue StandardError => e
            warn("ListingsCoverageQuery inventory load failed for #{@marketplace}: #{e.message}")
            []
          end

          def extract_source_product_ids_from_seed_text(text)
            ids = []
            text.each_line.with_index(1) do |line, lineno|
              raw = line.chomp
              next if raw.strip.empty?

              cols = raw.split("\t", -1)
              next if cols.size < 2

              json_str = cols[1].to_s.strip
              next if json_str.empty?

              obj = JSON.parse(json_str)
              id = obj["source_product_id"]
              next if id.nil?

              s = id.to_s.strip
              next if s.empty?

              ids << s
            rescue JSON::ParserError => e
              fb = source_product_id_fallback_from_json(json_str)
              if fb
                ids << fb
                warn("ListingsCoverageQuery seed line #{lineno}: invalid JSON, recovered source_product_id " \
                  "(#{e.message.to_s.byteslice(0, 120)})")
              else
                warn("ListingsCoverageQuery seed line #{lineno}: invalid JSON in column 2 (#{e.message})")
              end
            rescue StandardError => e
              warn("ListingsCoverageQuery seed line #{lineno}: #{e.class} #{e.message}")
            end
            ids.uniq.sort
          end

          def source_product_id_fallback_from_json(json_str)
            m = json_str.to_s.match(SOURCE_PRODUCT_ID_JSON_RE)
            return unless m

            s = m[1].to_s.strip
            EmTools::Plugins::AmazonLowestOffer::Patterns::AsinPattern.match?(s) || s.match?(/\A\d+\z/) ? s : nil
          end

          def read_seed_text_from_dir
            path = File.join(@seed_dir, "ebay_#{@marketplace}.txt")
            unless File.file?(path)
              warn("ListingsCoverageQuery: no seed file #{path}")
              return
            end

            File.read(path, encoding: "UTF-8")
          end

          def search_activity(seeds)
            unique = seeds.uniq.sort
            return empty_activity if unique.empty?

            totals = empty_activity
            batches = unique.each_slice(@terms_batch_size).to_a
            batches.each do |raw_batch|
              batch = id_terms_values(raw_batch)
              body = {
                timeout: "120s",
                size: 0,
                track_total_hits: true,
                query: seed_terms_filter_query(batch),
                aggs: activity_aggs,
              }
              response = @es_client.search(index: @index_name, body: body)
              partial = parse_activity(response)
              totals[:seed_listing_docs_total] += extract_total_hits(response)
              totals.each_key do |k|
                next if k == :seed_listing_docs_total
                next if k == :time_activity_docs_sum

                totals[k] += partial.fetch(k, 0).to_i
              end
            end

            totals[:time_activity_docs_sum] =
              TIME_ACTIVITY_DOC_BUCKET_KEYS.sum { |k| totals.fetch(k, 0).to_i }
            totals
          end

          def activity_aggs
            window_filters =
              if @snapshot_time
                clock = @snapshot_time
                {
                  last_24h: time_range_absolute(clock - 86_400, clock),
                  hours_24_to_48_ago: time_range_absolute(clock - 172_800, clock - 86_400),
                  hours_48_to_72h_ago: time_range_absolute(clock - 259_200, clock - 172_800),
                  hours_72_to_96h_ago: time_range_absolute(clock - 345_600, clock - 259_200),
                  hours_96_to_120h_ago: time_range_absolute(clock - 432_000, clock - 345_600),
                  older_than_120h: {
                    bool: {
                      must: [
                        { exists: { field: @time_field } },
                        { range: { @time_field => { lt: iso8601_z(clock - 432_000) } } },
                      ],
                    },
                  },
                  at_or_after_now: {
                    bool: {
                      must: [
                        { exists: { field: @time_field } },
                        { range: { @time_field => { gte: iso8601_z(clock) } } },
                      ],
                    },
                  },
                }
              else
                {
                  last_24h: time_range("now-24h", "now"),
                  hours_24_to_48_ago: time_range("now-48h", "now-24h"),
                  hours_48_to_72h_ago: time_range("now-72h", "now-48h"),
                  hours_72_to_96h_ago: time_range("now-96h", "now-72h"),
                  hours_96_to_120h_ago: time_range("now-120h", "now-96h"),
                  older_than_120h: {
                    bool: {
                      must: [
                        { exists: { field: @time_field } },
                        { range: { @time_field => { lt: "now-120h" } } },
                      ],
                    },
                  },
                  at_or_after_now: {
                    bool: {
                      must: [
                        { exists: { field: @time_field } },
                        { range: { @time_field => { gte: "now" } } },
                      ],
                    },
                  },
                }
              end

            {
              missing_time: {
                filter: {
                  bool: {
                    must_not: { exists: { field: @time_field } },
                  },
                },
              },
              with_time: {
                filter: { exists: { field: @time_field } },
                aggs: {
                  windows: {
                    filters: {
                      other_bucket: true,
                      other_bucket_key: "other_time_window",
                      filters: window_filters,
                    },
                  },
                },
              },
            }
          end

          def seed_terms_filter_query(batch)
            {
              bool: {
                filter: [
                  { terms: { @id_field => batch } },
                ],
              },
            }
          end

          def iso8601_z(time)
            time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
          end

          def time_range_absolute(t_gte, t_lt)
            {
              bool: {
                must: [
                  { exists: { field: @time_field } },
                  { range: { @time_field => { gte: iso8601_z(t_gte), lt: iso8601_z(t_lt) } } },
                ],
              },
            }
          end

          def time_range(range_gte, range_lt)
            {
              bool: {
                must: [
                  { exists: { field: @time_field } },
                  { range: { @time_field => { gte: range_gte, lt: range_lt } } },
                ],
              },
            }
          end

          def parse_activity(response)
            buckets =
              normalize_filter_agg_buckets(
                response.dig("aggregations", "with_time", "windows", "buckets"),
              )
            missing = response.dig("aggregations", "missing_time", "doc_count").to_i

            {
              time_last_24h: bucket_count(buckets, "last_24h"),
              time_24_to_48h_ago: bucket_count(buckets, "hours_24_to_48_ago"),
              time_48_to_72h_ago: bucket_count(buckets, "hours_48_to_72h_ago"),
              time_72_to_96h_ago: bucket_count(buckets, "hours_72_to_96h_ago"),
              time_96_to_120h_ago: bucket_count(buckets, "hours_96_to_120h_ago"),
              time_older_than_120h: bucket_count(buckets, "older_than_120h"),
              time_at_or_after_now: bucket_count(buckets, "at_or_after_now"),
              time_other_window: bucket_count(buckets, "other_time_window"),
              docs_missing_time: missing,
            }
          end

          def extract_total_hits(response)
            raw = response.dig("hits", "total")
            return raw.to_i if raw.is_a?(Numeric)
            return raw.to_i if raw.is_a?(String)
            return raw["value"].to_i if raw.is_a?(Hash)

            0
          end

          def normalize_filter_agg_buckets(raw)
            case raw
            when Hash
              raw.each_with_object({}) do |(k, v), h|
                next if k.nil?

                h[k.to_s] = v
              end
            when Array
              raw.each_with_object({}) do |b, h|
                next unless b.is_a?(Hash)

                name = b["key"] || b[:key]
                next if name.nil?

                h[name.to_s] = b
              end
            else
              {}
            end
          end

          def bucket_count(buckets, key)
            b = buckets[key.to_s]
            return 0 unless b

            bucket_doc_count(b)
          end

          def bucket_doc_count(bucket)
            return 0 unless bucket.is_a?(Hash)

            (bucket["doc_count"] || bucket[:doc_count]).to_i
          end

          def search_seed_coverage(seeds)
            unique = seeds.uniq.sort
            return empty_coverage if unique.empty?

            found_keys = Set.new
            batches = unique.each_slice(@terms_batch_size).to_a
            batches.each do |raw_batch|
              batch = id_terms_values(raw_batch)
              body = {
                timeout: "120s",
                size: 0,
                query: seed_terms_filter_query(batch),
                aggs: {
                  seed_ids_present: {
                    terms: {
                      field: @id_field,
                      size: @terms_batch_size,
                      min_doc_count: 1,
                    },
                  },
                },
              }
              response = @es_client.search(index: @index_name, body: body)
              buckets = response.dig("aggregations", "seed_ids_present", "buckets") || []
              buckets.each { |b| found_keys << normalize_id(b["key"]) }
            end

            seed_count = unique.length
            found_count = found_keys.size
            missing = [seed_count - found_count, 0].max
            missing_list = unique.reject { |id| found_keys.include?(normalize_id(id)) }

            {
              seed_ids_found_in_index: found_count,
              seed_ids_missing_from_index: missing,
              missing_seed_ids_file: persist_missing_ids_file(missing_list),
            }
          end

          def empty_activity
            {
              time_last_24h: 0,
              time_24_to_48h_ago: 0,
              time_48_to_72h_ago: 0,
              time_72_to_96h_ago: 0,
              time_96_to_120h_ago: 0,
              time_older_than_120h: 0,
              time_at_or_after_now: 0,
              time_other_window: 0,
              docs_missing_time: 0,
              seed_listing_docs_total: 0,
              time_activity_docs_sum: 0,
            }
          end

          def empty_coverage
            {
              seed_ids_found_in_index: nil,
              seed_ids_missing_from_index: nil,
              missing_seed_ids_file: nil,
            }
          end

          def persist_missing_ids_file(missing_ids)
            return if @missing_ids_dir.nil?
            return if missing_ids.empty?

            FileUtils.mkdir_p(@missing_ids_dir)
            path = File.join(@missing_ids_dir, "missing_product_ids_#{@marketplace}.txt")
            File.write(
              path,
              missing_ids_file_body(path, missing_ids),
              encoding: "UTF-8",
            )
            path
          rescue StandardError => e
            warn("ListingsCoverageQuery: could not write missing ids file: #{e.message}")
            nil
          end

          def missing_ids_file_body(path, missing_ids)
            lines = []
            lines << "# marketplace: #{@marketplace.upcase}"
            lines << "# index: #{@index_name}"
            lines << "# id_field: #{@id_field}"
            lines << "# path: #{path}"
            lines << "# missing_count: #{missing_ids.size}"
            lines << "# one product id per line (same values as used in Elasticsearch terms query)"
            lines << ""
            missing_ids.map { |id| normalize_id(id) }.sort.uniq.each { |id| lines << id }
            lines.join("\n")
          end

          def id_terms_values(raw_ids)
            raw_ids.map { |id| normalize_id(id) }
          end

          def normalize_id(id)
            id.to_s.strip
          end
        end
      end
    end
  end
end
