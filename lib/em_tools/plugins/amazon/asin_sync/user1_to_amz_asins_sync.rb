# frozen_string_literal: true

require "json"
require "set"
require "time"

module EmTools
  module Plugins
    module Amazon
      module AsinSync
        # Copies newly created ASIN rows from +user1_amz_asins+ (data cluster) into
        # +amz_asins_<marketplace>+ (primary cluster), skipping ASINs that already exist
        # in the destination index.
        class User1ToAmzAsinsSync
          Stats = Struct.new(
            :source_hits,
            :skipped_invalid,
            :skipped_existing,
            :indexed,
            :bulk_requests,
            :bulk_errors,
            keyword_init: true,
          )

          DEFAULT_SOURCE_INDEX = "user1_amz_asins"
          DEFAULT_SINCE_HOURS = 2
          DEFAULT_BULK_CHUNK = 500
          DEFAULT_TIME_FIELD = "created_at"

          def initialize(
            source_client:,
            target_client:,
            source_index: DEFAULT_SOURCE_INDEX,
            since_hours: DEFAULT_SINCE_HOURS,
            time_field: DEFAULT_TIME_FIELD,
            bulk_chunk: DEFAULT_BULK_CHUNK,
            marketplace: nil,
            full_scan: false,
            dry_run: false,
            logger: nil
          )
            @source = source_client
            @target = target_client
            @source_index = source_index.to_s.strip
            @full_scan = full_scan ? true : false
            @since_hours = [since_hours.to_f, 0.01].max unless @full_scan
            @time_field = time_field.to_s.strip
            @bulk_chunk = [bulk_chunk.to_i, 1].max
            @marketplace = normalize_marketplace(marketplace) if marketplace
            @dry_run = dry_run ? true : false
            @logger = logger
            @stats = Stats.new(
              source_hits: 0,
              skipped_invalid: 0,
              skipped_existing: 0,
              indexed: 0,
              bulk_requests: 0,
              bulk_errors: 0,
            )
            @pending = Hash.new { |h, k| h[k] = [] }
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

              sink_index = target_index(row[:marketplace])
              @pending[sink_index] << row
              flush_index!(sink_index) if @pending[sink_index].size >= @bulk_chunk
            end

            @pending.each_key { |index| flush_index!(index) }
            @stats
          end

          private

          def build_query
            must = @full_scan ? [] : [{ range: { @time_field => { gt: cutoff_time } } }]
            must << { term: { "marketplace" => @marketplace.upcase } } if @marketplace
            return { match_all: {} } if must.empty?

            { bool: { must: must } }
          end

          def cutoff_time
            (Time.now.utc - (@since_hours * 3600)).iso8601(3)
          end

          def log_scan_mode(query)
            if @full_scan
              mp = @marketplace ? " marketplace=#{@marketplace}" : ""
              log("scan source_index=#{@source_index} mode=full#{mp}")
              return
            end

            log(
              "scan source_index=#{@source_index} time_field=#{@time_field} " \
                "since_hours=#{@since_hours} gt=#{cutoff_time}",
            )
          end

          def extract_row(hit)
            src = hit["_source"] || {}
            asin = normalize_asin(src["asin"] || hit["_id"])
            marketplace = normalize_marketplace(src["marketplace"])
            return nil if asin.empty? || marketplace.empty?
            return nil unless valid_asin?(asin)

            {
              asin: asin,
              marketplace: marketplace,
              timestamp: pick_timestamp(src),
            }
          end

          def pick_timestamp(src)
            value = src[@time_field] || src["created_at"] || src["updated_at"]
            value = value.iso8601(3) if value.respond_to?(:iso8601)
            value.to_s.strip.empty? ? Time.now.utc.iso8601(3) : value.to_s
          end

          def target_index(marketplace)
            "amz_asins_#{marketplace}"
          end

          def flush_index!(sink_index)
            batch = @pending[sink_index]
            return if batch.empty?

            missing = filter_missing(sink_index, batch)
            @stats.skipped_existing += batch.size - missing.size
            index_missing!(sink_index, missing)
            @pending[sink_index].clear
          end

          def filter_missing(sink_index, batch)
            return batch if @dry_run

            unless @target.index_exists?(sink_index)
              log("target index missing, will create on write: #{sink_index}")
              return batch
            end

            ids = batch.map { |row| row[:asin] }
            resp = @target.mget(index: sink_index, ids: ids)
            existing = Set.new
            Array(resp["docs"]).each do |doc|
              existing << doc["_id"].to_s.upcase if doc["found"]
            end
            batch.reject { |row| existing.include?(row[:asin]) }
          end

          def index_missing!(sink_index, rows)
            return if rows.empty?

            if @dry_run
              @stats.indexed += rows.size
              return
            end

            lines = rows.flat_map do |row|
              body = { "asin" => row[:asin], "timestamp" => row[:timestamp] }
              [
                JSON.generate(index: { _index: sink_index, _id: row[:asin] }),
                JSON.generate(body),
              ]
            end
            @stats.bulk_requests += 1
            resp = @target.bulk(body: "#{lines.join("\n")}\n")
            errors = count_bulk_errors(resp)
            @stats.bulk_errors += errors
            @stats.indexed += rows.size - errors
          end

          def count_bulk_errors(resp)
            return 0 unless resp.is_a?(Hash)

            Array(resp["items"]).count { |item| item.values.first&.dig("error") }
          end

          def normalize_asin(value)
            asin = value.to_s.strip.upcase
            asin.include?("_") ? asin.split("_", 2).last.to_s : asin
          end

          def normalize_marketplace(value)
            value.to_s.strip.downcase
          end

          def valid_asin?(asin)
            EmTools::Plugins::Amazon::LowestOffer::Patterns::AsinPattern.match?(asin)
          end

          def log(message)
            @logger&.info(message)
          end
        end
      end
    end
  end
end
