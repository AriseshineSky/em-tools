# frozen_string_literal: true

require "fileutils"
require "json"
require "set"
require "time"

module EmTools
  module Plugins
    module Ebay
      module ProductSync
        # Copies product rows from +user1_ebay_products+ (data cluster) into
        # +ebay_us_products+ (primary cluster), keyed by Elasticsearch +_id+.
        class User1ToEbayUsProductsSync
          Stats = Struct.new(
            :source_hits,
            :skipped_invalid,
            :skipped_missing,
            :indexed,
            :bulk_requests,
            :bulk_errors,
            :sample_files,
            :sample_rows,
            keyword_init: true,
          )

          DEFAULT_SOURCE_INDEX = "user1_ebay_products"
          DEFAULT_TARGET_INDEX = "ebay_us_products"
          DEFAULT_SINCE_HOURS = 2
          DEFAULT_BULK_CHUNK = 500
          DEFAULT_TIME_FIELD = "date"
          DEFAULT_SAMPLE_INTERVAL = 1000
          DEFAULT_SAMPLE_DIR = "tmp/ebay_sync_user1_samples"

          def initialize(
            source_client:,
            target_client:,
            source_index: DEFAULT_SOURCE_INDEX,
            target_index: DEFAULT_TARGET_INDEX,
            since_hours: DEFAULT_SINCE_HOURS,
            since_date: nil,
            before_date: nil,
            time_field: DEFAULT_TIME_FIELD,
            bulk_chunk: DEFAULT_BULK_CHUNK,
            full_scan: false,
            skip_missing: false,
            dry_run: false,
            sample_dir: DEFAULT_SAMPLE_DIR,
            sample_interval: DEFAULT_SAMPLE_INTERVAL,
            debug: false,
            logger: nil
          )
            @source = source_client
            @target = target_client
            @source_index = source_index.to_s.strip
            @target_index = target_index.to_s.strip
            @full_scan = full_scan ? true : false
            @since_hours = [since_hours.to_f, 0.01].max unless @full_scan
            @since_date = normalize_time_value(since_date)
            @before_date = normalize_time_value(before_date)
            @time_field = time_field.to_s.strip
            @bulk_chunk = [bulk_chunk.to_i, 1].max
            @skip_missing = skip_missing ? true : false
            @dry_run = dry_run ? true : false
            @sample_dir = sample_dir.to_s.strip
            @sample_dir = nil if @sample_dir.empty?
            @sample_interval = sample_interval.nil? ? DEFAULT_SAMPLE_INTERVAL : [sample_interval.to_i, 1].max
            @sample_buffer = []
            @sample_batch_no = 0
            @debug = debug ? true : false
            @logger = logger
            @stats = Stats.new(
              source_hits: 0,
              skipped_invalid: 0,
              skipped_missing: 0,
              indexed: 0,
              bulk_requests: 0,
              bulk_errors: 0,
              sample_files: 0,
              sample_rows: 0,
            )
            @pending = []
          end

          def run!
            query = build_query
            log_scan_mode(query)

            @source.iterate_query(index: @source_index, query: query, batch_size: @bulk_chunk) do |hit|
              @stats.source_hits += 1
              row = extract_row(hit)
              unless row
                @stats.skipped_invalid += 1
                next
              end

              @pending << row
              flush! if @pending.size >= @bulk_chunk
            end

            flush!
            flush_samples!
            @stats
          end

          private

          def build_query
            filters = []
            unless @full_scan
              range = {}
              range[:gt] = cutoff_time unless cutoff_time.nil?
              range[:lt] = @before_date unless @before_date.nil?
              filters << { range: { @time_field => range } } unless range.empty?
            end
            return { match_all: {} } if filters.empty?

            { bool: { filter: filters } }
          end

          def cutoff_time
            return @since_date unless @since_date.nil?

            (Time.now.utc - (@since_hours * 3600)).iso8601(3)
          end

          def log_scan_mode(query)
            if @full_scan
              log("scan source_index=#{@source_index} target_index=#{@target_index} mode=full")
              return
            end

            parts = [
              "scan source_index=#{@source_index}",
              "target_index=#{@target_index}",
              "time_field=#{@time_field}",
            ]
            parts << "since_date=#{@since_date}" unless @since_date.nil?
            parts << "since_hours=#{@since_hours}" if @since_date.nil?
            parts << "before_date=#{@before_date}" unless @before_date.nil?
            parts << "gt=#{cutoff_time}" unless cutoff_time.nil?
            log(parts.join(" "))
          end

          def extract_row(hit)
            doc_id = normalize_id(hit["_id"])
            return nil if doc_id.empty?

            {
              doc_id: doc_id,
              body: hit["_source"] || {},
            }
          end

          def flush!
            return if @pending.empty?

            batch = @pending.dup
            @pending.clear
            rows = @skip_missing ? filter_existing(batch) : batch
            @stats.skipped_missing += batch.size - rows.size
            bulk_index!(rows)
          end

          def filter_existing(batch)
            return batch if @dry_run
            return batch unless @target.index_exists?(@target_index)

            ids = batch.map { |row| row[:doc_id] }
            resp = @target.mget(index: @target_index, ids: ids)
            existing = Set.new
            Array(resp["docs"]).each do |doc|
              existing << doc["_id"].to_s if doc["found"]
            end
            batch.select { |row| existing.include?(row[:doc_id]) }
          end

          def bulk_index!(rows)
            return if rows.empty?

            debug_log("bulk_index rows=#{rows.size} first=#{debug_row_summary(rows.first)}")

            if @dry_run
              @stats.indexed += rows.size
              record_samples!(rows)
              return
            end

            lines = rows.flat_map do |row|
              [
                JSON.generate(index: { _index: @target_index, _id: row[:doc_id] }),
                JSON.generate(row[:body]),
              ]
            end
            @stats.bulk_requests += 1
            resp = @target.bulk(body: "#{lines.join("\n")}\n")
            errors = count_bulk_errors(resp)
            debug_log("bulk response errors=#{errors} indexed=#{rows.size - errors}")
            @stats.bulk_errors += errors
            indexed = rows.size - errors
            @stats.indexed += indexed
            record_samples!(rows.first(indexed)) if indexed.positive?
          end

          def record_samples!(rows)
            return if @sample_dir.nil?

            rows.each do |row|
              @sample_buffer << {
                _id: row[:doc_id],
                date: extract_date(row[:body]),
              }
              next if @sample_buffer.size < @sample_interval

              write_sample_file!
            end
          end

          def flush_samples!
            return if @sample_dir.nil? || @sample_buffer.empty?

            write_sample_file!
          end

          def write_sample_file!
            return if @sample_buffer.empty?

            FileUtils.mkdir_p(@sample_dir)
            @sample_batch_no += 1
            path = File.join(@sample_dir, format("batch_%03d.tsv", @sample_batch_no))
            lines = ["_id\t#{@time_field}"]
            @sample_buffer.each do |row|
              lines << "#{row[:_id]}\t#{row[:date]}"
            end
            File.write(path, "#{lines.join("\n")}\n", encoding: "UTF-8")
            @stats.sample_files += 1
            @stats.sample_rows += @sample_buffer.size
            log("sample checkpoint rows=#{@sample_buffer.size} path=#{path}")
            @sample_buffer.clear
          end

          def extract_date(body)
            return "" unless body.is_a?(Hash)

            value = body[@time_field] || body[@time_field.to_sym]
            value = value.iso8601(3) if value.respond_to?(:iso8601)
            value.to_s
          end

          def count_bulk_errors(resp)
            return 0 unless resp.is_a?(Hash)

            Array(resp["items"]).count { |item| item.values.first&.dig("error") }
          end

          def normalize_id(value)
            value.to_s.strip
          end

          def normalize_time_value(value)
            raw = value.to_s.strip
            return nil if raw.empty?

            parsed = Time.parse(raw).utc
            parsed.iso8601(3)
          rescue ArgumentError
            raise EmTools::Core::Errors::ConfigurationError,
              "invalid date/time value #{raw.inspect} (expected ISO8601, e.g. 2026-05-18T14:45:15+00:00)"
          end

          def log(message)
            @logger&.info(message)
          end

          def debug_log(message)
            return unless @debug

            @logger&.debug(message)
          end

          def debug_row_summary(row)
            return nil unless row

            "#{row[:doc_id]} date=#{extract_date(row[:body]).inspect}"
          end
        end
      end
    end
  end
end
