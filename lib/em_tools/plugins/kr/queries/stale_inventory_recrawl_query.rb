# frozen_string_literal: true

require "time"

module EmTools
  module Plugins
    module Kr
      module Queries
        # Finds 11ST inventory SKUs that are missing or stale in +user1_kr_products+
        # (``source=elevenst``) by ``updated_at``, and resolves PDP URLs for Scrapyd.
        class StaleInventoryRecrawlQuery
          DEFAULT_INVENTORY_INDEX = "em_inventory"
          DEFAULT_PRODUCTS_INDEX = "user1_kr_products"
          DEFAULT_INVENTORY_SOURCE = "11ST"
          DEFAULT_PRODUCTS_SOURCE = "elevenst"
          DEFAULT_STALE_DAYS = 7
          DEFAULT_TIME_FIELD = "updated_at"
          DEFAULT_TARGET_ID_TEMPLATE = "elevenst_%<id>s"
          DEFAULT_BULK_CHUNK = 500
          PDP_URL_TEMPLATE = "https://www.11st.co.kr/products/%<id>s"

          RecrawlItem = Struct.new(:product_id, :url, :reason, :updated_at, keyword_init: true)

          def initialize(
            es_client:,
            snapshot_time: nil,
            inventory_index: nil,
            products_index: nil,
            inventory_source: nil,
            inventory_source_field: nil,
            inventory_product_id_field: nil,
            products_source: nil,
            stale_days: nil,
            time_field: nil,
            target_id_template: nil,
            bulk_chunk: nil,
            max_urls: nil
          )
            @es_client = es_client
            @snapshot_time = (snapshot_time || Time.now.utc).utc
            @inventory_index = pick(inventory_index, "ELEVENST_RECRAWL_INVENTORY_INDEX", DEFAULT_INVENTORY_INDEX)
            @products_index = pick(products_index, "ELEVENST_RECRAWL_PRODUCTS_INDEX", DEFAULT_PRODUCTS_INDEX)
            @inventory_source = pick(inventory_source, "ELEVENST_RECRAWL_INVENTORY_SOURCE", DEFAULT_INVENTORY_SOURCE)
            @inventory_source_field = pick(
              inventory_source_field,
              "ELEVENST_RECRAWL_INVENTORY_SOURCE_FIELD",
              "source.keyword",
            )
            @inventory_product_id_field = pick(
              inventory_product_id_field,
              "ELEVENST_RECRAWL_INVENTORY_PRODUCT_ID_FIELD",
              "source_product_id",
            )
            @products_source = pick(products_source, "ELEVENST_RECRAWL_PRODUCTS_SOURCE", DEFAULT_PRODUCTS_SOURCE)
            @time_field = pick(time_field, "ELEVENST_RECRAWL_TIME_FIELD", "updated_at")
            @stale_days = resolve_stale_days(stale_days)
            @target_id_template = pick(
              target_id_template,
              "ELEVENST_RECRAWL_TARGET_ID_TEMPLATE",
              DEFAULT_TARGET_ID_TEMPLATE,
            )
            raw_chunk = bulk_chunk
            raw_chunk = ENV["ELEVENST_RECRAWL_BULK_CHUNK"].to_s.strip if raw_chunk.nil?
            raw_chunk = DEFAULT_BULK_CHUNK.to_s if raw_chunk.to_s.strip.empty?
            @bulk_chunk = [raw_chunk.to_i, 1].max
            @max_urls = resolve_max_urls(max_urls)
          end

          def fetch
            ids = load_inventory_ids
            stats = empty_stats.merge(
              inventory_index: @inventory_index,
              products_index: @products_index,
              inventory_source: @inventory_source,
              products_source: @products_source,
              time_field: @time_field,
              stale_days: @stale_days,
              inventory_total: ids.length,
            )
            return stats if ids.empty?

            ids.each_slice(@bulk_chunk) { |batch| classify_batch!(stats, batch) }
            stats[:recrawl_items] = stats[:recrawl_items].first(@max_urls) if @max_urls
            stats
          rescue StandardError => e
            empty_stats.merge(
              inventory_index: @inventory_index,
              products_index: @products_index,
              inventory_source: @inventory_source,
              products_source: @products_source,
              time_field: @time_field,
              stale_days: @stale_days,
              error: e.message.to_s.byteslice(0, 200),
            )
          end

          private

          def pick(cli_value, env_key, default)
            raw = cli_value.to_s.strip
            raw = ENV[env_key].to_s.strip if raw.empty?
            raw.empty? ? default : raw
          end

          def resolve_stale_days(cli_value)
            raw = cli_value.to_s.strip
            raw = ENV["ELEVENST_RECRAWL_STALE_DAYS"].to_s.strip if raw.empty?
            raw = DEFAULT_STALE_DAYS.to_s if raw.empty?
            days = Integer(raw)
            raise EmTools::Core::Errors::ConfigurationError, "stale-days must be >= 0" if days.negative?

            days
          rescue ArgumentError
            raise EmTools::Core::Errors::ConfigurationError,
              "stale-days must be an integer (got #{raw.inspect})"
          end

          def resolve_max_urls(cli_value)
            raw = cli_value.to_s.strip
            raw = ENV["ELEVENST_RECRAWL_MAX_URLS"].to_s.strip if raw.empty?
            return nil if raw.empty?

            cap = Integer(raw)
            cap.positive? ? cap : nil
          rescue ArgumentError
            raise EmTools::Core::Errors::ConfigurationError,
              "max-urls must be a positive integer (got #{raw.inspect})"
          end

          def load_inventory_ids
            loader = EmTools::Plugins::Ebay::Sources::InventoryProductIdLoader.new(
              es_client: @es_client,
              index: @inventory_index,
              source_field: @inventory_source_field,
              source_terms: [@inventory_source, @inventory_source.downcase, @inventory_source.upcase].uniq,
              product_id_field: @inventory_product_id_field,
            )
            loader.load("kr")
          end

          def classify_batch!(stats, batch)
            resp = @es_client.mget(index: @products_index, ids: batch.map { |id| target_doc_id(id) })
            by_requested_id = {}
            Array(resp["docs"]).each do |doc|
              by_requested_id[doc["_id"].to_s] = doc
            end

            batch.each do |source_product_id|
              doc = by_requested_id[target_doc_id(source_product_id)]
              if doc.nil? || !doc["found"]
                stats[:missing_products] += 1
                stats[:recrawl_items] << build_item(source_product_id, nil, "missing")
                next
              end

              source = doc["_source"] || {}
              unless source_matches?(source)
                stats[:skipped_wrong_source] += 1
                next
              end

              updated_at = source[@time_field] || source[@time_field.to_sym]
              if stale?(updated_at)
                stats[:stale_products] += 1
                stats[:recrawl_items] << build_item(source_product_id, source["url"], "stale", updated_at)
              else
                stats[:fresh_products] += 1
              end
            end
          end

          def build_item(product_id, url, reason, updated_at = nil)
            RecrawlItem.new(
              product_id: product_id.to_s.strip,
              url: resolve_url(product_id, url),
              reason: reason,
              updated_at: updated_at,
            )
          end

          def resolve_url(product_id, url)
            raw = url.to_s.strip
            return normalize_url(raw) unless raw.empty?

            format(PDP_URL_TEMPLATE, id: product_id.to_s.strip)
          end

          def normalize_url(url)
            u = url.to_s.strip
            return u if u.start_with?("https://")

            u.sub(%r{\Ahttp://}i, "https://")
          end

          def source_matches?(source)
            return true if @products_source.to_s.strip.empty?

            body = source.is_a?(Hash) ? source : {}
            actual = body["source"] || body[:source]
            actual.to_s == @products_source
          end

          def stale?(value)
            return true if @stale_days.zero?

            parsed = parse_time(value)
            return true if parsed.nil?

            (@snapshot_time - parsed) >= (@stale_days * 86_400)
          end

          def parse_time(value)
            return value.utc if value.is_a?(Time)

            raw = value.to_s.strip
            return nil if raw.empty?

            Time.parse(raw).utc
          rescue ArgumentError
            nil
          end

          def target_doc_id(source_product_id)
            format(@target_id_template, id: source_product_id.to_s.strip)
          end

          def empty_stats
            {
              inventory_total: 0,
              fresh_products: 0,
              stale_products: 0,
              missing_products: 0,
              skipped_wrong_source: 0,
              recrawl_items: [],
            }
          end
        end
      end
    end
  end
end
