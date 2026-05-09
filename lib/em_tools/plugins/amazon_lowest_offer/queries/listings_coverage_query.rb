# frozen_string_literal: true

require 'fileutils'
require 'json'

module EmTools
  module Plugins
    module AmazonLowestOffer
      module Queries
        # Time-window activity and seed coverage for lowest_offer_listings_* indices (no Rails).
        # Activity counts are scoped to documents whose ASIN is in the seed list (+terms+ on +@asin_field+).
        #
        # Units: +seed_asins_unique+ / +seed_asins_missing_from_index+ / +seed_asins_found_in_index+ are **ASIN**
        # counts from the seed file (+missing+ means no listing doc for that ASIN). Do **not** add +missing+ to
        # listing-document sums. The +time_*+, +docs_missing_time+, +time_at_or_after_now+ fields are **listing
        # document** counts. Their sum is +time_activity_docs_sum+ and should equal +seed_listing_docs_total+.
        # Compare document sums to +seed_asins_unique+ only if you expect one listing per seed ASIN.
        #
        # Activity/coverage ES queries use +bool.filter+ +terms+ on +@asin_field+ with **seed ASINs only** (no broad query).
        # Optional +snapshot_time+ (UTC) freezes time-window aggs to that instant for one publish; omit to use ES +now+.
        #
        # ID source +LOWEST_OFFER_ID_SOURCE+ (default +seed+): +seed+ uses files / +seed_text_fetcher+ as below;
        # +inventory+ loads distinct Amazon ASINs from Elasticsearch +em_inventory+ (see +LowestOfferInventoryAsinLoader+).
        #
        # Seeds: +seed_dir+ looks for +amz_<mp>.txt+ then +ebay_<mp>.txt+. Each non-empty line: tab-separated,
        # **column 2** (0-based index 1) is JSON; +source_product_id+ is taken as the ASIN for ES +terms+.
        # If +JSON.parse+ fails (truncated lines, etc.), a regex fallback reads +"source_product_id":"…"+ when it looks like an ASIN.
        # +LOWEST_OFFER_ASIN_FIELD+ default +asin.keyword+; values uppercased to match +_source.asin+.
        # Large seeds: +LOWEST_OFFER_TERMS_BATCH_SIZE+ (default 2000, max 5000) controls ASINs per ES request.
        # Missing seed ASINs (not in index): written under +LOWEST_OFFER_MISSING_ASINS_DIR+ (default
        # +./tmp/lowest_offer_missing_asins+), file +missing_asins_<mp>.txt+. Set +LOWEST_OFFER_WRITE_MISSING_ASINS=false+ to disable.
        class ListingsCoverageQuery
          DEFAULT_MARKETPLACES = %w[in it ae ca mx de jp uk us].freeze

          TERMS_BATCH_SIZE_MIN = 200
          TERMS_BATCH_SIZE_MAX = 5000
          TERMS_BATCH_SIZE_DEFAULT = 2000

          # When column-2 JSON is truncated, try to read +"source_product_id":"…"+ before giving up on the line.
          SOURCE_PRODUCT_ID_JSON_RE = /"source_product_id"\s*:\s*"([^"\\\s]+)"/

          # Doc-count fields for the seed +terms+ query; +time_other_window+ is ES +filters+ +other_bucket+ (see +activity_aggs+).
          TIME_ACTIVITY_DOC_BUCKET_KEYS = %i[
            time_last_24h
            time_24_to_48h_ago
            time_48_to_72h_ago
            time_older_than_72h
            time_at_or_after_now
            time_other_window
            docs_missing_time
          ].freeze

          # +seed_text_fetcher+ — optional Proc (marketplace lowercase String) -> seed file String (in-memory).
          # +seed_dir+ — optional directory with +amz_<mp>.txt+ ; used when set before +seed_text_fetcher+.
          # +id_source+ — +seed+ (default) or +inventory+ (+LOWEST_OFFER_ID_SOURCE+).
          def initialize(es_client:, marketplaces: nil, time_field: nil, asin_field: nil, seed_dir: nil,
                         seed_text_fetcher: nil, snapshot_time: nil, id_source: nil,
                         inventory_index: nil, inventory_source_field: nil, inventory_source_terms: nil,
                         inventory_product_id_field: nil, inventory_marketplace_field: nil,
                         inventory_max_hits: nil)
            @es_client = es_client
            @seed_dir = (seed_dir || ENV['LOWEST_OFFER_SEED_DIR']).to_s.strip
            @seed_text_fetcher = seed_text_fetcher
            @snapshot_time = snapshot_time&.utc
            @id_source = (id_source || ENV['LOWEST_OFFER_ID_SOURCE'] || 'seed').to_s.strip.downcase
            configure_inventory_options!(
              inventory_index: inventory_index,
              inventory_source_field: inventory_source_field,
              inventory_source_terms: inventory_source_terms,
              inventory_product_id_field: inventory_product_id_field,
              inventory_marketplace_field: inventory_marketplace_field,
              inventory_max_hits: inventory_max_hits
            )
            @marketplaces = if marketplaces&.any?
                              marketplaces.map { |m| m.to_s.downcase }
                            else
                              env_list = parse_marketplace_list(ENV['LOWEST_OFFER_MARKETPLACES'])
                              env_list.empty? ? DEFAULT_MARKETPLACES : env_list
                            end
            tf = time_field.to_s.strip
            @time_field = tf.empty? ? ENV.fetch('LOWEST_OFFER_TIME_FIELD', 'time') : tf
            af = asin_field.to_s.strip
            @asin_field = af.empty? ? ENV.fetch('LOWEST_OFFER_ASIN_FIELD', 'asin.keyword') : af
            raw_bs = ENV.fetch('LOWEST_OFFER_TERMS_BATCH_SIZE', TERMS_BATCH_SIZE_DEFAULT.to_s).to_i
            @terms_batch_size = raw_bs.clamp(TERMS_BATCH_SIZE_MIN, TERMS_BATCH_SIZE_MAX)

            @write_missing_asins = ENV['LOWEST_OFFER_WRITE_MISSING_ASINS'] != 'false'
            dir_raw = ENV['LOWEST_OFFER_MISSING_ASINS_DIR'].to_s.strip
            @missing_asins_dir =
              if !@write_missing_asins || dir_raw == '-'
                nil
              elsif dir_raw.empty?
                File.expand_path('tmp/lowest_offer_missing_asins', Dir.pwd)
              else
                File.expand_path(dir_raw)
              end
          end

          def fetch_all
            @marketplaces.map { |mp| fetch_marketplace(mp.to_s.downcase) }
          end

          def fetch_marketplace(mp)
            index = "lowest_offer_listings_#{mp}_new"
            seeds = load_seed_asins(mp)
            row = base_row(mp, index, seeds)
            activity = search_activity(index, seeds)
            coverage = search_seed_coverage(index, seeds, marketplace: mp) if seeds.any?
            row.merge!(activity)
            row.merge!(coverage || empty_coverage)
            row
          rescue StandardError => e
            warn "ListingsCoverageQuery failed for #{index}: #{e.class} #{e.message}"
            seeds = load_seed_asins(mp)
            base_row(mp, index, seeds).merge(empty_activity).merge(empty_coverage)
                                      .merge(error: e.message.to_s.byteslice(0, 200))
          end

          private

          def parse_marketplace_list(raw)
            return DEFAULT_MARKETPLACES if raw.nil? || raw.to_s.strip.empty?

            raw.split(',').map(&:strip).reject(&:empty?).map(&:downcase)
          end

          def base_row(mp, index, seeds)
            {
              marketplace: mp.upcase,
              index_name: index,
              id_source: @id_source,
              inventory_index: (@id_source == 'inventory' ? @inventory_index : nil),
              seed_asins_loaded: seeds.length,
              seed_asins_unique: seeds.uniq.length,
              seed_file_present: seed_file_present_for_marketplace?(mp)
            }
          end

          # When +@seed_dir+ is set: whether +amz_<mp>.txt+ or +ebay_<mp>.txt+ exists (before parsing). +nil+ if seeds come only from +seed_text_fetcher+ (e.g. GCS).
          def seed_file_present_for_marketplace?(mp)
            return nil if @id_source == 'inventory'
            return nil if @seed_dir.empty?

            %W[amz_#{mp}.txt ebay_#{mp}.txt].any? { |name| File.file?(File.join(@seed_dir, name)) }
          end

          def load_seed_asins(mp)
            return load_asins_from_inventory(mp) if @id_source == 'inventory'

            text =
              if !@seed_dir.empty?
                read_seed_text_from_dir(mp)
              elsif @seed_text_fetcher
                @seed_text_fetcher.call(mp)
              end
            return [] if text.nil? || text.to_s.empty?

            extract_source_product_ids_from_seed_text(text.to_s)
          rescue StandardError => e
            warn "ListingsCoverageQuery seed load failed for #{mp}: #{e.message}"
            []
          end

          # rubocop:disable Metrics/ParameterLists
          def configure_inventory_options!(inventory_index:, inventory_source_field:, inventory_source_terms:,
                                           inventory_product_id_field:, inventory_marketplace_field:, inventory_max_hits:)
            @inventory_index = (inventory_index || ENV['LOWEST_OFFER_INVENTORY_INDEX']).to_s.strip
            @inventory_index = 'em_inventory' if @inventory_index.empty?
            sf = (inventory_source_field || ENV['LOWEST_OFFER_INVENTORY_SOURCE_FIELD']).to_s.strip
            @inventory_source_field = sf.empty? ? 'source.keyword' : sf
            terms = inventory_source_terms || parse_csv_env('LOWEST_OFFER_INVENTORY_AMAZON_SOURCES')
            @inventory_source_terms = terms
            pf = (inventory_product_id_field || ENV['LOWEST_OFFER_INVENTORY_PRODUCT_ID_FIELD']).to_s.strip
            @inventory_product_id_field = pf.empty? ? 'source_product_id' : pf
            mf = (inventory_marketplace_field || ENV['LOWEST_OFFER_INVENTORY_MARKETPLACE_FIELD']).to_s.strip
            @inventory_marketplace_field = mf.empty? ? nil : mf
            @inventory_max_hits = inventory_max_hits
          end
          # rubocop:enable Metrics/ParameterLists

          def parse_csv_env(key)
            ENV[key].to_s.split(',').map(&:strip).reject(&:empty?)
          end

          def load_asins_from_inventory(mp)
            loader = LowestOfferInventoryAsinLoader.new(
              es_client: @es_client,
              index: @inventory_index,
              source_field: @inventory_source_field,
              source_terms: @inventory_source_terms,
              product_id_field: @inventory_product_id_field,
              marketplace_field: @inventory_marketplace_field,
              max_hits: @inventory_max_hits
            )
            loader.load(mp)
          rescue StandardError => e
            warn "ListingsCoverageQuery inventory load failed for #{mp}: #{e.message}"
            []
          end

          # One row per line: split on TAB, second column is JSON object with string key +source_product_id+.
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
              id = obj['source_product_id']
              next if id.nil?

              s = id.to_s.strip
              next if s.empty?

              ids << s.upcase
            rescue JSON::ParserError => e
              fb = source_product_id_fallback_from_json(json_str)
              if fb
                ids << fb.upcase
                warn "ListingsCoverageQuery seed line #{lineno}: invalid JSON, recovered source_product_id " \
                     "(#{e.message.to_s.byteslice(0, 120)})"
              else
                warn "ListingsCoverageQuery seed line #{lineno}: invalid JSON in column 2 (#{e.message})"
              end
            rescue StandardError => e
              warn "ListingsCoverageQuery seed line #{lineno}: #{e.class} #{e.message}"
            end
            ids.uniq.sort
          end

          def source_product_id_fallback_from_json(json_str)
            m = json_str.to_s.match(SOURCE_PRODUCT_ID_JSON_RE)
            return nil unless m

            s = m[1].to_s.strip
            EmTools::Plugins::AmazonLowestOffer::Patterns::AsinPattern.match?(s) ? s : nil
          end

          def seed_asin_like?(s)
            EmTools::Plugins::AmazonLowestOffer::Patterns::AsinPattern.match?(s)
          end

          def read_seed_text_from_dir(mp)
            %W[amz_#{mp}.txt ebay_#{mp}.txt].each do |name|
              path = File.join(@seed_dir, name)
              next unless File.file?(path)

              return File.read(path, encoding: 'UTF-8')
            end
            warn "ListingsCoverageQuery: no seed file for #{mp} under #{@seed_dir} " \
                 '(expected amz_<mp>.txt or ebay_<mp>.txt)'
            nil
          end

          def search_activity(index, seeds)
            unique = seeds.uniq.sort
            return empty_activity if unique.empty?

            totals = empty_activity
            batches = unique.each_slice(@terms_batch_size).to_a
            batches.each do |raw_batch|
              batch = asin_terms_values(raw_batch)
              body = {
                timeout: '120s',
                size: 0,
                track_total_hits: true,
                query: seed_terms_filter_query(batch),
                aggs: activity_aggs
              }
              response = @es_client.search(index: index, body: body)
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
                  older_than_72h: {
                    bool: {
                      must: [
                        { exists: { field: @time_field } },
                        { range: { @time_field => { lt: iso8601_z(clock - 259_200) } } }
                      ]
                    }
                  },
                  at_or_after_now: {
                    bool: {
                      must: [
                        { exists: { field: @time_field } },
                        { range: { @time_field => { gte: iso8601_z(clock) } } }
                      ]
                    }
                  }
                }
              else
                {
                  last_24h: time_range('now-24h', 'now'),
                  hours_24_to_48_ago: time_range('now-48h', 'now-24h'),
                  hours_48_to_72h_ago: time_range('now-72h', 'now-48h'),
                  older_than_72h: {
                    bool: {
                      must: [
                        { exists: { field: @time_field } },
                        { range: { @time_field => { lt: 'now-72h' } } }
                      ]
                    }
                  },
                  at_or_after_now: {
                    bool: {
                      must: [
                        { exists: { field: @time_field } },
                        { range: { @time_field => { gte: 'now' } } }
                      ]
                    }
                  }
                }
              end

            {
              missing_time: {
                filter: {
                  bool: {
                    must_not: { exists: { field: @time_field } }
                  }
                }
              },
              with_time: {
                filter: { exists: { field: @time_field } },
                aggs: {
                  windows: {
                    filters: {
                      other_bucket: true,
                      other_bucket_key: 'other_time_window',
                      filters: window_filters
                    }
                  }
                }
              }
            }
          end

          # +terms+ on seed ASIN batch only (filter context, no scoring).
          def seed_terms_filter_query(batch)
            {
              bool: {
                filter: [
                  { terms: { @asin_field => batch } }
                ]
              }
            }
          end

          def iso8601_z(time)
            time.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
          end

          def time_range_absolute(t_gte, t_lt)
            {
              bool: {
                must: [
                  { exists: { field: @time_field } },
                  { range: { @time_field => { gte: iso8601_z(t_gte), lt: iso8601_z(t_lt) } } }
                ]
              }
            }
          end

          def time_range(gte, lt)
            {
              bool: {
                must: [
                  { exists: { field: @time_field } },
                  { range: { @time_field => { gte: gte, lt: lt } } }
                ]
              }
            }
          end

          def parse_activity(response)
            buckets =
              normalize_filter_agg_buckets(
                response.dig('aggregations', 'with_time', 'windows', 'buckets')
              )
            missing = response.dig('aggregations', 'missing_time', 'doc_count').to_i

            {
              time_last_24h: bucket_count(buckets, 'last_24h'),
              time_24_to_48h_ago: bucket_count(buckets, 'hours_24_to_48_ago'),
              time_48_to_72h_ago: bucket_count(buckets, 'hours_48_to_72h_ago'),
              time_older_than_72h: bucket_count(buckets, 'older_than_72h'),
              time_at_or_after_now: bucket_count(buckets, 'at_or_after_now'),
              time_other_window: bucket_count(buckets, 'other_time_window'),
              docs_missing_time: missing
            }
          end

          def extract_total_hits(response)
            raw = response.dig('hits', 'total')
            return raw.to_i if raw.is_a?(Numeric)
            return raw.to_i if raw.is_a?(String)
            return raw['value'].to_i if raw.is_a?(Hash)

            0
          end

          # +filters+ agg may return +buckets+ as a keyed Hash or an Array of +{ "key" => name, "doc_count" => n }+.
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

                name = b['key'] || b[:key]
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

            (bucket['doc_count'] || bucket[:doc_count]).to_i
          end

          def search_seed_coverage(index, seeds, marketplace:)
            unique = seeds.uniq.sort
            return empty_coverage if unique.empty?

            found_keys = Set.new
            batches = unique.each_slice(@terms_batch_size).to_a
            batches.each do |raw_batch|
              batch = asin_terms_values(raw_batch)
              body = {
                timeout: '120s',
                size: 0,
                query: seed_terms_filter_query(batch),
                aggs: {
                  # Exact count of seed ASINs in this batch that appear in the index (one bucket per value).
                  seed_asins_present: {
                    terms: {
                      field: @asin_field,
                      size: @terms_batch_size,
                      min_doc_count: 1
                    }
                  }
                }
              }
              response = @es_client.search(index: index, body: body)
              buckets = response.dig('aggregations', 'seed_asins_present', 'buckets') || []
              buckets.each { |b| found_keys << b['key'].to_s.upcase }
            end

            seed_count = unique.length
            found_count = found_keys.size
            missing = [seed_count - found_count, 0].max
            missing_list = unique.reject { |a| found_keys.include?(a.to_s.upcase) }

            {
              seed_asins_found_in_index: found_count,
              seed_asins_missing_from_index: missing,
              missing_asins_file: persist_missing_asins_file(marketplace, index, missing_list)
            }
          end

          def empty_activity
            {
              time_last_24h: 0,
              time_24_to_48h_ago: 0,
              time_48_to_72h_ago: 0,
              time_older_than_72h: 0,
              time_at_or_after_now: 0,
              time_other_window: 0,
              docs_missing_time: 0,
              seed_listing_docs_total: 0,
              time_activity_docs_sum: 0
            }
          end

          def empty_coverage
            {
              seed_asins_found_in_index: nil,
              seed_asins_missing_from_index: nil,
              missing_asins_file: nil
            }
          end

          def persist_missing_asins_file(marketplace, index, missing_asins)
            return nil if @missing_asins_dir.nil?
            return nil if missing_asins.empty?

            FileUtils.mkdir_p(@missing_asins_dir)
            mkt = marketplace.to_s.downcase
            path = File.join(@missing_asins_dir, "missing_asins_#{mkt}.txt")
            File.write(
              path,
              missing_asins_file_body(mkt, index, missing_asins),
              encoding: 'UTF-8'
            )
            path
          rescue StandardError => e
            warn "ListingsCoverageQuery: could not write missing ASINs file: #{e.message}"
            nil
          end

          def missing_asins_file_body(mkt, index, missing_asins)
            lines = []
            lines << "# marketplace: #{mkt.upcase}"
            lines << "# index: #{index}"
            lines << "# asin_field: #{@asin_field}"
            lines << "# missing_count: #{missing_asins.size}"
            lines << '# one ASIN per line (same values as used in Elasticsearch terms query)'
            lines << ''
            missing_asins.map { |asin| asin.to_s.upcase }.sort.uniq.each { |asin| lines << asin }
            lines.join("\n")
          end

          def asin_terms_values(raw_asins)
            raw_asins.map { |asin| asin.to_s.upcase }
          end

          class << self
            # Same marketplace resolution as +initialize+ (rake + publish_snapshot+ args first).
            # rubocop:disable Metrics/PerceivedComplexity
            def marketplaces_for_publish(cli_marketplaces_csv)
              list = cli_marketplaces_csv.to_s.split(',').map(&:strip).reject(&:empty?).map(&:downcase)
              return list if list.any?

              env_list = ENV['LOWEST_OFFER_MARKETPLACES'].to_s.split(',').map(&:strip).reject(&:empty?).map(&:downcase)
              return env_list if env_list.any?

              DEFAULT_MARKETPLACES.dup
            end
            # rubocop:enable Metrics/PerceivedComplexity
          end
        end
      end
    end
  end
end
