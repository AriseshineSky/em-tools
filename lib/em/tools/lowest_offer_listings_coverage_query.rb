# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'set'

module Em
  module Tools
    # Time-window activity and seed coverage for lowest_offer_listings_* indices (no Rails).
    # Activity counts are scoped to documents whose ASIN is in the seed list (+terms+ on +@asin_field+).
    #
    # Units: +seed_asins_unique+ / +seed_asins_missing_from_index+ / +seed_asins_found_in_index+ are **ASIN**
    # counts from the seed file (+missing+ means no listing doc for that ASIN). Do **not** add +missing+ to
    # listing-document sums. The +time_*+, +docs_missing_time+, +time_at_or_after_now+ fields are **listing
    # document** counts. Their sum is +time_activity_docs_sum+ and should equal +seed_listing_docs_total+.
    # Compare document sums to +seed_asins_unique+ only if you expect one listing per seed ASIN.
    #
    # Seeds: +seed_dir+ looks for +amz_<mp>.txt+ then +ebay_<mp>.txt+. Each non-empty line: tab-separated,
    # **column 2** (0-based index 1) is JSON; +source_product_id+ is taken as the ASIN for ES +terms+.
    # +LOWEST_OFFER_ASIN_FIELD+ default +asin.keyword+; values uppercased to match +_source.asin+.
    # Large seeds: +LOWEST_OFFER_TERMS_BATCH_SIZE+ (default 2000, max 5000) controls ASINs per ES request.
    # Missing seed ASINs (not in index): written under +LOWEST_OFFER_MISSING_ASINS_DIR+ (default
    # +./tmp/lowest_offer_missing_asins+), file +missing_asins_<mp>.txt+. Set +LOWEST_OFFER_WRITE_MISSING_ASINS=false+ to disable.
    # Debug: +LOWEST_OFFER_DEBUG_ACTIVITY_AGGS=1+ logs +missing_time+ / +with_time+ JSON to stderr for **every** batch.
    # Optional +LOWEST_OFFER_DEBUG_ACTIVITY_AGGS_MAX_BYTES+ (default 200000, clamp 10000..2000000) truncates stderr JSON.
    # +LOWEST_OFFER_DEBUG_ACTIVITY_AGGS_DIR+ — if set, writes one JSON file per activity batch under
    # +<expanded_dir>/<sanitized_index_name>/activity_batch_NNNN_of_MMMM.json+ with this batch's ASIN list and ES aggs slice.
    # Optional +LOWEST_OFFER_DEBUG_ACTIVITY_AGGS_FILE_MAX_BYTES+ (default 20000000, clamp 100000..200000000) truncates each file.
    class LowestOfferListingsCoverageQuery
      DEFAULT_MARKETPLACES = %w[us ca mx ae de in it jp uk].freeze

      TERMS_BATCH_SIZE_MIN = 200
      TERMS_BATCH_SIZE_MAX = 5000
      TERMS_BATCH_SIZE_DEFAULT = 2000

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

      # ES +filters+ bucket names under +activity_aggs+ -> +windows+ (must match +parse_activity+ / +other_bucket_key+).
      WINDOW_FILTERS_ES_BUCKET_KEYS = %w[
        last_24h
        hours_24_to_48_ago
        hours_48_to_72h_ago
        older_than_72h
        at_or_after_now
        other_time_window
      ].freeze

      # +seed_text_fetcher+ — optional Proc (marketplace lowercase String) -> seed file String (in-memory).
      # +seed_dir+ — optional directory with +amz_<mp>.txt+ ; used when set before +seed_text_fetcher+.
      def initialize(es_client:, marketplaces: nil, time_field: nil, asin_field: nil, seed_dir: nil,
                     seed_text_fetcher: nil)
        @es_client = es_client
        @seed_dir = (seed_dir || ENV['LOWEST_OFFER_SEED_DIR']).to_s.strip
        @seed_text_fetcher = seed_text_fetcher
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
        warn "LowestOfferListingsCoverageQuery failed for #{index}: #{e.class} #{e.message}"
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
          seed_asins_loaded: seeds.length,
          seed_asins_unique: seeds.uniq.length
        }
      end

      def load_seed_asins(mp)
        text =
          if !@seed_dir.empty?
            read_seed_text_from_dir(mp)
          elsif @seed_text_fetcher
            @seed_text_fetcher.call(mp)
          end
        return [] if text.nil? || text.to_s.empty?

        extract_source_product_ids_from_seed_text(text.to_s)
      rescue StandardError => e
        warn "LowestOfferListingsCoverageQuery seed load failed for #{mp}: #{e.message}"
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
          warn "LowestOfferListingsCoverageQuery seed line #{lineno}: invalid JSON in column 2 (#{e.message})"
        rescue StandardError => e
          warn "LowestOfferListingsCoverageQuery seed line #{lineno}: #{e.class} #{e.message}"
        end
        ids.uniq
      end

      def read_seed_text_from_dir(mp)
        %W[amz_#{mp}.txt ebay_#{mp}.txt].each do |name|
          path = File.join(@seed_dir, name)
          next unless File.file?(path)

          return File.read(path, encoding: 'UTF-8')
        end
        warn "LowestOfferListingsCoverageQuery: no seed file for #{mp} under #{@seed_dir} " \
             '(expected amz_<mp>.txt or ebay_<mp>.txt)'
        nil
      end

      def search_activity(index, seeds)
        unique = seeds.uniq
        return empty_activity if unique.empty?

        totals = empty_activity
        with_time_doc_count_batches = 0
        # Sum of +doc_count+ over every entry in normalized +windows.buckets+ (can include non-leaf / extra keys).
        windows_filters_values_doc_sum_batches = 0
        # Same six named filters as +parse_activity+ (should match snapshot +time_*+ sums excl. +docs_missing_time+).
        windows_filters_known_doc_sum_batches = 0
        extra_window_bucket_keys = Set.new
        last_windows_bucket_keys = []
        debug_activity_aggs = ENV['LOWEST_OFFER_DEBUG_ACTIVITY_AGGS'] == '1'
        activity_debug_dir = ENV['LOWEST_OFFER_DEBUG_ACTIVITY_AGGS_DIR'].to_s.strip
        activity_debug_dir = nil if activity_debug_dir.empty?
        activity_debug_dir = File.expand_path(activity_debug_dir) if activity_debug_dir
        activity_debug_out_dir = nil
        if activity_debug_dir
          activity_debug_out_dir = File.join(activity_debug_dir, sanitize_index_for_path(index))
          FileUtils.mkdir_p(activity_debug_out_dir)
          puts "LowestOfferListingsCoverageQuery: activity aggs debug files -> #{activity_debug_out_dir}"
        end
        last_activity_agg_slice = nil
        last_activity_batch_idx = nil
        last_activity_batch_asin_count = nil
        skew_activity_agg_slice = nil
        skew_activity_batch_idx = nil
        skew_activity_batch_asin_count = nil
        batches = unique.each_slice(@terms_batch_size).to_a
        total_batches = batches.size
        batches.each_with_index do |raw_batch, idx|
          if (idx % 10).zero? && total_batches > 1
            puts "LowestOfferListingsCoverageQuery[#{index}] activity batch #{idx + 1}/#{total_batches} " \
                 "(~#{@terms_batch_size} ASINs each)"
          end
          batch = asin_terms_values(raw_batch)
          body = {
            timeout: '120s',
            size: 0,
            track_total_hits: true,
            query: {
              terms: {
                @asin_field => batch
              }
            },
            aggs: activity_aggs
          }
          response = @es_client.search(index: index, body: body)
          with_time_doc_count_batches +=
            response.dig('aggregations', 'with_time', 'doc_count').to_i
          windows_buckets =
            normalize_filter_agg_buckets(
              response.dig('aggregations', 'with_time', 'windows', 'buckets')
            )
          windows_filters_values_doc_sum_batches +=
            windows_buckets.values.sum { |b| bucket_doc_count(b) }
          windows_filters_known_doc_sum_batches +=
            WINDOW_FILTERS_ES_BUCKET_KEYS.sum { |ek| bucket_count(windows_buckets, ek) }
          windows_buckets.each_key do |k|
            extra_window_bucket_keys << k unless WINDOW_FILTERS_ES_BUCKET_KEYS.include?(k)
          end
          last_windows_bucket_keys = windows_buckets.keys.sort
          partial = parse_activity(response, windows_buckets_normalized: windows_buckets)
          totals[:seed_listing_docs_total] += extract_total_hits(response)
          totals.each_key do |k|
            next if k == :seed_listing_docs_total
            next if k == :time_activity_docs_sum

            totals[k] += partial.fetch(k, 0).to_i
          end

          batch_values = windows_buckets.values.sum { |b| bucket_doc_count(b) }
          batch_known = WINDOW_FILTERS_ES_BUCKET_KEYS.sum { |ek| bucket_count(windows_buckets, ek) }
          agg_slice = slice_activity_aggregations_for_debug(response)
          last_activity_agg_slice = agg_slice
          last_activity_batch_idx = idx + 1
          last_activity_batch_asin_count = batch.size

          if activity_debug_out_dir
            write_activity_batch_debug_file(
              activity_debug_out_dir,
              index: index,
              batch_index: idx + 1,
              total_batches: total_batches,
              asins: batch,
              response: response,
              windows_buckets: windows_buckets,
              partial: partial,
              batch_known: batch_known,
              batch_values: batch_values
            )
          end

          if debug_activity_aggs
            log_activity_aggregations_debug(
              index,
              "DEBUG_ACTIVITY_AGGS batch #{idx + 1}/#{total_batches} ASINs=#{batch.size} " \
              "hits.total=#{extract_total_hits(response)} " \
              "batch_known=#{batch_known} batch_values=#{batch_values}",
              agg_slice
            )
          elsif activity_debug_out_dir.nil? && skew_activity_agg_slice.nil? && batch_values != batch_known
            skew_activity_agg_slice = agg_slice
            skew_activity_batch_idx = idx + 1
            skew_activity_batch_asin_count = batch.size
            warn "LowestOfferListingsCoverageQuery[#{index}]: activity batch #{skew_activity_batch_idx}/#{total_batches} " \
                 "windows buckets values_sum(#{batch_values}) != known_sum(#{batch_known}); " \
                 'dumping missing_time/with_time aggregations once (set LOWEST_OFFER_DEBUG_ACTIVITY_AGGS_DIR=... or =1)'
            log_activity_aggregations_debug(
              index,
              "skew_batch=#{skew_activity_batch_idx} ASINs=#{skew_activity_batch_asin_count}",
              skew_activity_agg_slice
            )
          end
        end

        totals[:time_activity_docs_sum] =
          TIME_ACTIVITY_DOC_BUCKET_KEYS.sum { |k| totals.fetch(k, 0).to_i }
        values_ne_known = windows_filters_values_doc_sum_batches != windows_filters_known_doc_sum_batches
        if totals[:time_activity_docs_sum] != totals[:seed_listing_docs_total] || values_ne_known
          miss = totals[:docs_missing_time].to_i
          windows_only = totals[:time_activity_docs_sum] - miss
          sum_with_and_missing = with_time_doc_count_batches + miss
          extras = extra_window_bucket_keys.to_a.sort
          keys_seen = last_windows_bucket_keys.empty? ? '(none)' : last_windows_bucket_keys.join(',')
          warn "LowestOfferListingsCoverageQuery[#{index}]: time_activity_docs_sum " \
               "(#{totals[:time_activity_docs_sum]}) != seed_listing_docs_total " \
               "(#{totals[:seed_listing_docs_total]}); " \
               "with_time.doc_count(sum_batches)=#{with_time_doc_count_batches} " \
               "docs_missing_time(sum)=#{miss} " \
               "with_time+missing=#{sum_with_and_missing} " \
               "time_windows_excl_missing=#{windows_only} " \
               "windows.filters_known_doc_count(sum_batches)=#{windows_filters_known_doc_sum_batches} " \
               "windows.filters_values_doc_count(sum_batches)=#{windows_filters_values_doc_sum_batches} " \
               "unknown_window_bucket_keys=#{extras.empty? ? '(none)' : extras.join(',')} " \
               "last_batch_window_bucket_keys=#{keys_seen} " \
               '(known sum should match time_windows_excl_missing; if values sum is higher, extra keys or ' \
               'non-leaf bucket objects are being summed. If with_time+missing!=seed_total, compare hits.total ' \
               'to filter aggs.)'
          if activity_debug_out_dir.nil? && (skew_activity_agg_slice.nil? || skew_activity_batch_idx != last_activity_batch_idx)
            log_activity_aggregations_debug(
              index,
              "last_batch=#{last_activity_batch_idx}/#{total_batches} ASINs=#{last_activity_batch_asin_count} " \
              '(aggregations slice; compare when totals skew)',
              last_activity_agg_slice
            )
          end
        end
        totals
      end

      def activity_aggs
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
                  filters: {
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
                    # Completes the partition with last_24h (lt now): docs at or after "now" (clock skew / future).
                    at_or_after_now: {
                      bool: {
                        must: [
                          { exists: { field: @time_field } },
                          { range: { @time_field => { gte: 'now' } } }
                        ]
                      }
                    }
                  }
                }
              }
            }
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

      # Subset of ES search response for stderr debugging (+missing_time+, +with_time+ only).
      def slice_activity_aggregations_for_debug(response)
        aggs = response['aggregations'] || response[:aggregations]
        return {} unless aggs.is_a?(Hash)

        missing = aggs['missing_time'] || aggs[:missing_time]
        with_t = aggs['with_time'] || aggs[:with_time]
        { 'missing_time' => missing, 'with_time' => with_t }
      end

      def sanitize_index_for_path(index)
        s = index.to_s.gsub(/[^a-zA-Z0-9_.-]+/, '_')
        s = s.byteslice(0, 200) if s.bytesize > 200

        s.empty? ? 'index' : s
      end

      def activity_aggs_debug_json_max_bytes
        raw = ENV['LOWEST_OFFER_DEBUG_ACTIVITY_AGGS_MAX_BYTES'].to_s.strip
        lim = raw.empty? ? 200_000 : raw.to_i
        lim.clamp(10_000, 2_000_000)
      end

      def activity_aggs_debug_file_json_max_bytes
        raw = ENV['LOWEST_OFFER_DEBUG_ACTIVITY_AGGS_FILE_MAX_BYTES'].to_s.strip
        lim = raw.empty? ? 20_000_000 : raw.to_i
        lim.clamp(100_000, 200_000_000)
      end

      def deep_stringify_keys(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), h|
            h[k.to_s] = deep_stringify_keys(v)
          end
        when Array
          obj.map { |e| deep_stringify_keys(e) }
        else
          obj
        end
      end

      def format_debug_json(payload, max_bytes:)
        s = JSON.pretty_generate(deep_stringify_keys(payload))
        return s if max_bytes.nil? || s.bytesize <= max_bytes

        "#{s.byteslice(0, max_bytes)}\n... truncated (#{s.bytesize} bytes, cap #{max_bytes}) ..."
      end

      def format_activity_aggs_debug_json(payload)
        format_debug_json(payload, max_bytes: activity_aggs_debug_json_max_bytes)
      end

      def write_activity_batch_debug_file(out_dir, index:, batch_index:, total_batches:, asins:, response:,
                                          windows_buckets:, partial:, batch_known:, batch_values:)
        fname = format('activity_batch_%04d_of_%04d.json', batch_index, total_batches)
        path = File.join(out_dir, fname)
        payload = {
          'captured_at' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
          'index_name' => index.to_s,
          'asin_field' => @asin_field.to_s,
          'time_field' => @time_field.to_s,
          'terms_batch_size' => @terms_batch_size,
          'batch_index' => batch_index,
          'total_batches' => total_batches,
          'asin_count' => asins.size,
          'asins' => asins.map(&:to_s),
          'hits_total' => extract_total_hits(response),
          'with_time_doc_count' => response.dig('aggregations', 'with_time', 'doc_count').to_i,
          'batch_windows_filters_known_doc_sum' => batch_known.to_i,
          'batch_windows_filters_values_doc_sum' => batch_values.to_i,
          'partial_activity_counts' => partial.transform_keys(&:to_s),
          'windows_bucket_keys' => windows_buckets.keys.sort,
          'windows_buckets_doc_counts' => windows_buckets.transform_values { |b| bucket_doc_count(b) },
          'aggregations' => slice_activity_aggregations_for_debug(response)
        }
        json = format_debug_json(payload, max_bytes: activity_aggs_debug_file_json_max_bytes)
        File.write(path, json, encoding: 'UTF-8')
      rescue StandardError => e
        warn "LowestOfferListingsCoverageQuery: could not write activity debug file #{path}: #{e.message}"
      end

      def log_activity_aggregations_debug(index, label, payload)
        $stderr.puts "LowestOfferListingsCoverageQuery[#{index}] #{label}"
        $stderr.puts format_activity_aggs_debug_json(payload)
      end

      # +windows_buckets_normalized+ — optional Hash from +normalize_filter_agg_buckets+ to avoid parsing twice per batch.
      def parse_activity(response, windows_buckets_normalized: nil)
        buckets =
          windows_buckets_normalized ||
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
        unique = seeds.uniq
        return empty_coverage if unique.empty?

        found_keys = Set.new
        batches = unique.each_slice(@terms_batch_size).to_a
        total_batches = batches.size
        batches.each_with_index do |raw_batch, idx|
          if (idx % 10).zero? && total_batches > 1
            puts "LowestOfferListingsCoverageQuery[#{index}] coverage batch #{idx + 1}/#{total_batches}"
          end
          batch = asin_terms_values(raw_batch)
          body = {
            timeout: '120s',
            size: 0,
            query: {
              terms: {
                @asin_field => batch
              }
            },
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
        mp = marketplace.to_s.downcase
        path = File.join(@missing_asins_dir, "missing_asins_#{mp}.txt")
        File.write(
          path,
          missing_asins_file_body(mp, index, missing_asins),
          encoding: 'UTF-8'
        )
        puts "LowestOfferListingsCoverageQuery: wrote #{missing_asins.size} missing ASINs -> #{path}"
        path
      rescue StandardError => e
        warn "LowestOfferListingsCoverageQuery: could not write missing ASINs file: #{e.message}"
        nil
      end

      def missing_asins_file_body(mp, index, missing_asins)
        lines = []
        lines << "# marketplace: #{mp.upcase}"
        lines << "# index: #{index}"
        lines << "# asin_field: #{@asin_field}"
        lines << "# missing_count: #{missing_asins.size}"
        lines << '# one ASIN per line (same values as used in Elasticsearch terms query)'
        lines << ''
        missing_asins.map { |a| a.to_s.upcase }.sort.uniq.each { |a| lines << a }
        lines.join("\n")
      end

      def asin_terms_values(raw_asins)
        raw_asins.map { |asin| asin.to_s.upcase }
      end

      class << self
        # Same marketplace resolution as +initialize+ (rake + publish_snapshot+ args first).
        def marketplaces_for_publish(cli_marketplaces_csv)
          list = cli_marketplaces_csv.to_s.split(',').map(&:strip).reject(&:empty?).map(&:downcase)
          return list if list.any?

          env_list = ENV['LOWEST_OFFER_MARKETPLACES'].to_s.split(',').map(&:strip).reject(&:empty?).map(&:downcase)
          return env_list if env_list.any?

          DEFAULT_MARKETPLACES.dup
        end
      end
    end
  end
end
