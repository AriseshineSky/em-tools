# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module EmTools
  module Plugins
    module Catalog
      module ProductSync
        # Sync Docmorris crawl rows from +user1_de_products+ (data cluster) into
        # slim +catalog_products+ docs on the primary cluster.
        #
        # Target +_id+ = +docmorris_{product_id}+ (aligned with em-tasks /
        # em-repricer listing.docmorris).
        class User1DocmorrisToCatalogProductsSync
          Stats = Struct.new(
            :source_hits,
            :skipped_invalid,
            :skipped_missing,
            :skipped_stale,
            :indexed,
            :bulk_requests,
            :bulk_errors,
            :sample_files,
            :sample_rows,
            keyword_init: true,
          )

          DEFAULT_SOURCE_INDEX = "user1_de_products"
          DEFAULT_TARGET_INDEX = "catalog_products"
          DEFAULT_PRODUCT_SOURCE = "docmorris"
          DEFAULT_SOURCE_TERM_FIELD = "source.keyword"
          DEFAULT_SOURCE_TERM_VALUE = "docmorris"
          DEFAULT_MARKETPLACE = "de"
          DEFAULT_CURRENCY = "EUR"
          DEFAULT_SINCE_HOURS = 36
          DEFAULT_BULK_CHUNK = 500
          DEFAULT_TIME_FIELD = "date"
          DEFAULT_SAMPLE_INTERVAL = 1000
          DEFAULT_SAMPLE_DIR = "tmp/catalog_sync_docmorris_samples"
          CATALOG_SCHEMA_VERSION = "1"

          OPTIONAL_STD_FIELDS = %w[
            sku url title brand upc
            shipping_days_min shipping_days_max has_only_default_variant
          ].freeze
          EXTRAS_FIELDS = %w[
            categories weight width height length reviews rating
          ].freeze

          CATALOG_PRODUCTS_MAPPINGS = {
            "dynamic" => false,
            "properties" => {
              "source" => { "type" => "keyword" },
              "product_id" => { "type" => "keyword" },
              "marketplace" => { "type" => "keyword" },
              "sku" => { "type" => "keyword" },
              "price" => { "type" => "double" },
              "shipping_fee" => { "type" => "double" },
              "currency" => { "type" => "keyword" },
              "available_qty" => { "type" => "long" },
              "existence" => { "type" => "boolean" },
              "date" => { "type" => "date" },
              "url" => { "type" => "keyword", "index" => false, "doc_values" => false },
              "title" => {
                "type" => "text",
                "fields" => { "keyword" => { "type" => "keyword", "ignore_above" => 256 } },
              },
              "brand" => { "type" => "keyword" },
              "upc" => { "type" => "keyword" },
              "shipping_days_min" => { "type" => "integer" },
              "shipping_days_max" => { "type" => "integer" },
              "has_only_default_variant" => { "type" => "boolean" },
              "synced_at" => { "type" => "date" },
              "schema_version" => { "type" => "keyword" },
              "created_at" => { "type" => "date" },
              "updated_at" => { "type" => "date" },
              "extras" => { "type" => "object", "enabled" => false },
            },
          }.freeze

          def initialize(
            source_client:,
            target_client:,
            source_index: DEFAULT_SOURCE_INDEX,
            target_index: DEFAULT_TARGET_INDEX,
            product_source: DEFAULT_PRODUCT_SOURCE,
            source_term_field: DEFAULT_SOURCE_TERM_FIELD,
            source_term_value: DEFAULT_SOURCE_TERM_VALUE,
            marketplace: DEFAULT_MARKETPLACE,
            default_currency: DEFAULT_CURRENCY,
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
            @product_source = product_source.to_s.strip
            @source_term_field = source_term_field.to_s.strip
            @source_term_value = source_term_value.to_s.strip
            @marketplace = marketplace.to_s.strip.downcase
            @default_currency = default_currency.to_s.strip
            @default_currency = DEFAULT_CURRENCY if @default_currency.empty?
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
              skipped_stale: 0,
              indexed: 0,
              bulk_requests: 0,
              bulk_errors: 0,
              sample_files: 0,
              sample_rows: 0,
            )
            @pending = []
          end

          def run!
            ensure_target_index! unless @dry_run
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

          def source_row_to_catalog_doc(source_body, hit_id: nil)
            body = source_body.is_a?(Hash) ? source_body : {}
            product_id = body["product_id"].to_s.strip
            if product_id.empty? && hit_id
              raw = hit_id.to_s.strip
              prefix = "#{@product_source}_"
              if raw.start_with?(prefix)
                product_id = raw[prefix.length..]
              end
            end
            return nil if product_id.to_s.strip.empty?

            qty = body.key?("available_qty") ? body["available_qty"] : body["quantity"]
            existence = body.key?("existence") ? body["existence"] : true
            existence = existence == false ? false : true

            date_val = body["date"] || body["time"]
            doc = {
              "source" => @product_source,
              "product_id" => product_id.to_s,
              "marketplace" => (@marketplace.empty? ? body["marketplace"].to_s.strip.downcase : @marketplace),
              "price" => as_float(body["price"]),
              "shipping_fee" => as_float(body["shipping_fee"]),
              "currency" => (body["currency"].to_s.strip.empty? ? @default_currency : body["currency"].to_s.strip),
              "existence" => existence,
              "synced_at" => Time.now.utc.iso8601(3),
              "schema_version" => CATALOG_SCHEMA_VERSION,
            }
            qty_i = as_int_or_nil(qty)
            doc["available_qty"] = qty_i unless qty_i.nil?
            doc["date"] = date_val unless date_val.nil?

            OPTIONAL_STD_FIELDS.each do |key|
              value = body[key]
              next if value.nil? || value == ""

              doc[key] = value
            end

            extras = {}
            EXTRAS_FIELDS.each do |key|
              value = body[key]
              next if value.nil? || value == ""

              extras[key] = value
            end
            doc["extras"] = extras unless extras.empty?

            {
              doc_id: catalog_doc_id(product_id),
              body: doc,
            }
          end

          private

          def catalog_doc_id(product_id)
            "#{@product_source}_#{product_id}"
          end

          def ensure_target_index!
            return if @target.index_exists?(@target_index)

            log("create target index=#{@target_index}")
            @target.create_index(
              @target_index,
              body: { "mappings" => CATALOG_PRODUCTS_MAPPINGS },
            )
          end

          def build_query
            filters = [
              { term: { @source_term_field => @source_term_value } },
            ]
            unless @full_scan
              range = {}
              range[:gt] = cutoff_time unless cutoff_time.nil?
              range[:lt] = @before_date unless @before_date.nil?
              filters << { range: { @time_field => range } } unless range.empty?
            end
            { bool: { filter: filters } }
          end

          def cutoff_time
            return @since_date unless @since_date.nil?

            (Time.now.utc - (@since_hours * 3600)).iso8601(3)
          end

          def log_scan_mode(query)
            parts = [
              "scan source_index=#{@source_index}",
              "target_index=#{@target_index}",
              "product_source=#{@product_source}",
              "term=#{@source_term_field}=#{@source_term_value}",
            ]
            if @full_scan
              parts << "mode=full"
            else
              parts << "time_field=#{@time_field}"
              parts << "since_date=#{@since_date}" unless @since_date.nil?
              parts << "since_hours=#{@since_hours}" if @since_date.nil?
              parts << "before_date=#{@before_date}" unless @before_date.nil?
              parts << "gt=#{cutoff_time}" unless cutoff_time.nil?
            end
            log(parts.join(" "))
            debug_log("query=#{query.inspect}")
          end

          def extract_row(hit)
            source_body = hit["_source"] || {}
            source_row_to_catalog_doc(source_body, hit_id: hit["_id"])
          end

          def flush!
            return if @pending.empty?

            batch = @pending.dup
            @pending.clear
            rows = filter_for_index(batch)
            bulk_index!(rows)
          end

          def filter_for_index(batch)
            return batch unless @target.index_exists?(@target_index)

            ids = batch.map { |row| row[:doc_id] }
            resp = @target.mget(index: @target_index, ids: ids)
            target_by_id = {}
            Array(resp["docs"]).each do |doc|
              target_by_id[doc["_id"].to_s] = doc if doc["found"]
            end

            batch.select do |row|
              target_doc = target_by_id[row[:doc_id]]
              if target_doc.nil?
                if @skip_missing
                  @stats.skipped_missing += 1
                  false
                else
                  true
                end
              elsif source_newer?(row[:body], target_doc["_source"])
                true
              else
                @stats.skipped_stale += 1
                false
              end
            end
          end

          def source_newer?(source_body, target_body)
            source_time = parse_doc_time(source_body)
            target_time = parse_doc_time(target_body)
            return true if target_time.nil?
            return true if source_time.nil?

            source_time > target_time
          end

          def parse_doc_time(body)
            return nil unless body.is_a?(Hash)

            value = body[@time_field] || body[@time_field.to_sym]
            return nil if value.nil?

            parse_time_value(value)
          end

          def parse_time_value(value)
            return value.utc if value.is_a?(Time)

            raw = value.to_s.strip
            return nil if raw.empty?

            Time.parse(raw).utc
          rescue ArgumentError
            nil
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

          def as_float(value, default = 0.0)
            return default if value.nil? || value == ""

            Float(value)
          rescue ArgumentError, TypeError
            default
          end

          def as_int_or_nil(value)
            return nil if value.nil? || value == ""

            Integer(value)
          rescue ArgumentError, TypeError
            nil
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
