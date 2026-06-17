# frozen_string_literal: true

require "set"
require "time"

module EmTools
  module Plugins
    module Kr
      module Queries
        # Compares 11ST inventory SKUs against crawled +user1_kr_products+ docs and
        # measures how fresh the price update timestamp (+date+ by default) is.
        class PriceFreshnessQuery
          DEFAULT_INVENTORY_INDEX = "em_inventory"
          DEFAULT_PRODUCTS_INDEX = "user1_kr_products"
          DEFAULT_INVENTORY_SOURCE = "11ST"
          DEFAULT_PRODUCTS_SOURCE = "elevenst"
          DEFAULT_TIME_FIELD = "date"
          DEFAULT_THRESHOLD_DAYS = 7
          DEFAULT_TARGET_ID_TEMPLATE = "elevenst_%<id>s"
          DEFAULT_BULK_CHUNK = 500

          def initialize(
            es_client:,
            snapshot_time: nil,
            inventory_index: nil,
            products_index: nil,
            inventory_source: nil,
            inventory_source_field: nil,
            inventory_product_id_field: nil,
            products_source: nil,
            time_field: nil,
            threshold_days: nil,
            target_id_template: nil,
            bulk_chunk: nil
          )
            @es_client = es_client
            @snapshot_time = (snapshot_time || Time.now.utc).utc
            @inventory_index = pick(inventory_index, "ELEVENST_PRICE_FRESHNESS_INVENTORY_INDEX", DEFAULT_INVENTORY_INDEX)
            @products_index = pick(products_index, "ELEVENST_PRICE_FRESHNESS_PRODUCTS_INDEX", DEFAULT_PRODUCTS_INDEX)
            @inventory_source = pick(inventory_source, "ELEVENST_PRICE_FRESHNESS_INVENTORY_SOURCE", DEFAULT_INVENTORY_SOURCE)
            @inventory_source_field = pick(
              inventory_source_field,
              "ELEVENST_PRICE_FRESHNESS_INVENTORY_SOURCE_FIELD",
              "source.keyword",
            )
            @inventory_product_id_field = pick(
              inventory_product_id_field,
              "ELEVENST_PRICE_FRESHNESS_INVENTORY_PRODUCT_ID_FIELD",
              "source_product_id",
            )
            @products_source = pick(products_source, "ELEVENST_PRICE_FRESHNESS_PRODUCTS_SOURCE", DEFAULT_PRODUCTS_SOURCE)
            @time_field = pick(time_field, "ELEVENST_PRICE_FRESHNESS_TIME_FIELD", DEFAULT_TIME_FIELD)
            @threshold_days = resolve_threshold_days(threshold_days)
            @target_id_template = pick(
              target_id_template,
              "ELEVENST_PRICE_FRESHNESS_TARGET_ID_TEMPLATE",
              DEFAULT_TARGET_ID_TEMPLATE,
            )
            raw_chunk = bulk_chunk
            raw_chunk = ENV["ELEVENST_PRICE_FRESHNESS_BULK_CHUNK"].to_s.strip if raw_chunk.nil?
            raw_chunk = DEFAULT_BULK_CHUNK.to_s if raw_chunk.to_s.strip.empty?
            @bulk_chunk = [raw_chunk.to_i, 1].max
          end

          def fetch_row
            ids = load_inventory_ids
            stats = empty_stats.merge(
              data_source: @inventory_source,
              inventory_index: @inventory_index,
              products_index: @products_index,
              products_source: @products_source,
              time_field: @time_field,
              fresh_threshold_days: @threshold_days,
              inventory_total: ids.length,
            )
            return stats if ids.empty?

            ids.each_slice(@bulk_chunk) { |batch| classify_batch!(stats, batch) }
            finalize_stats!(stats)
            stats
          rescue StandardError => e
            empty_stats.merge(
              data_source: @inventory_source,
              inventory_index: @inventory_index,
              products_index: @products_index,
              products_source: @products_source,
              time_field: @time_field,
              fresh_threshold_days: @threshold_days,
              error: e.message.to_s.byteslice(0, 200),
            )
          end

          private

          def pick(cli_value, env_key, default)
            raw = cli_value.to_s.strip
            raw = ENV[env_key].to_s.strip if raw.empty?
            raw.empty? ? default : raw
          end

          def resolve_threshold_days(cli_value)
            raw = cli_value.to_s.strip
            raw = ENV["ELEVENST_PRICE_FRESHNESS_THRESHOLD_DAYS"].to_s.strip if raw.empty?
            raw = DEFAULT_THRESHOLD_DAYS.to_s if raw.empty?
            days = Float(raw)
            raise EmTools::Core::Errors::ConfigurationError, "threshold-days must be > 0" unless days.positive?

            days
          rescue ArgumentError
            raise EmTools::Core::Errors::ConfigurationError,
              "threshold-days must be a number (got #{raw.inspect})"
          end

          def load_inventory_ids
            loader = EmTools::Plugins::Ebay::Sources::InventoryProductIdLoader.new(
              es_client: @es_client,
              index: @inventory_index,
              source_field: @inventory_source_field,
              source_terms: [@inventory_source],
              product_id_field: @inventory_product_id_field,
            )
            loader.load("kr")
          end

          def classify_batch!(stats, batch)
            resp = @es_client.mget(index: @products_index, ids: batch.map { |id| target_doc_id(id) })
            by_requested_id = {}
            Array(resp["docs"]).each do |doc|
              by_requested_id[doc["_id"].to_s] = doc if doc["found"]
            end

            batch.each do |source_product_id|
              doc = by_requested_id[target_doc_id(source_product_id)]
              next unless doc && source_matches?(doc["_source"])

              stats[:products_found] += 1
              classify_found_doc!(stats, doc["_source"])
            end
          end

          def source_matches?(source)
            return true if @products_source.to_s.strip.empty?

            body = source.is_a?(Hash) ? source : {}
            actual = body["source"] || body[:source]
            actual.to_s == @products_source
          end

          def classify_found_doc!(stats, source)
            body = source.is_a?(Hash) ? source : {}
            parsed = parse_time(body[@time_field] || body[@time_field.to_sym])
            if parsed.nil?
              stats[:docs_missing_time] += 1
              return
            end

            age_seconds = @snapshot_time - parsed
            if age_seconds <= 86_400
              stats[:time_last_24h] += 1
            elsif age_seconds <= 259_200
              stats[:time_1_to_3d] += 1
            elsif age_seconds <= (@threshold_days * 86_400)
              stats[:time_3_to_threshold] += 1
            else
              stats[:stale_older_than_threshold] += 1
              stats[:time_older_than_threshold] += 1
            end

            return unless age_seconds <= (@threshold_days * 86_400)

            stats[:fresh_within_threshold] += 1
          end

          def finalize_stats!(stats)
            stats[:products_missing] = [stats[:inventory_total] - stats[:products_found], 0].max
            found = stats[:products_found]
            fresh = stats[:fresh_within_threshold]
            stats[:fresh_pct] = found.positive? ? ((fresh * 100.0) / found).round(2) : 0.0
            stats[:stale_pct] = found.positive? ? ((stats[:stale_older_than_threshold] * 100.0) / found).round(2) : 0.0
          end

          def target_doc_id(source_product_id)
            format(@target_id_template, id: source_product_id.to_s.strip)
          end

          def parse_time(value)
            return value.utc if value.is_a?(Time)

            raw = value.to_s.strip
            return nil if raw.empty?

            Time.parse(raw).utc
          rescue ArgumentError
            nil
          end

          def empty_stats
            {
              inventory_total: 0,
              products_found: 0,
              products_missing: 0,
              fresh_within_threshold: 0,
              stale_older_than_threshold: 0,
              docs_missing_time: 0,
              time_last_24h: 0,
              time_1_to_3d: 0,
              time_3_to_threshold: 0,
              time_older_than_threshold: 0,
              fresh_pct: 0.0,
              stale_pct: 0.0,
            }
          end
        end
      end
    end
  end
end
