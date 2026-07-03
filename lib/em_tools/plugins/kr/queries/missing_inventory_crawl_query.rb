# frozen_string_literal: true

module EmTools
  module Plugins
    module Kr
      module Queries
        # Inventory rows with no crawled product doc in +user1_kr_products+ (``source=elevenst``).
        class MissingInventoryCrawlQuery
          DEFAULT_INVENTORY_INDEX = "em_inventory"
          DEFAULT_PRODUCTS_INDEX = "user1_kr_products"
          DEFAULT_INVENTORY_SOURCE = "11ST"
          DEFAULT_PRODUCTS_SOURCE = "elevenst"
          DEFAULT_TARGET_ID_TEMPLATE = "elevenst_%<id>s"
          DEFAULT_BULK_CHUNK = 500
          PDP_URL_TEMPLATE = "https://www.11st.co.kr/products/%<id>s"

          CrawlRow = Struct.new(
            :source,
            :source_product_id,
            :source_product_url,
            :crawl_url,
            keyword_init: true,
          )

          def initialize(
            es_client:,
            inventory_index: nil,
            products_index: nil,
            inventory_source: nil,
            inventory_source_field: nil,
            inventory_product_id_field: nil,
            products_source: nil,
            target_id_template: nil,
            bulk_chunk: nil,
            max_rows: nil
          )
            @es_client = es_client
            @inventory_index = pick(inventory_index, "ELEVENST_MISSING_CRAWL_INVENTORY_INDEX", DEFAULT_INVENTORY_INDEX)
            @products_index = pick(products_index, "ELEVENST_MISSING_CRAWL_PRODUCTS_INDEX", DEFAULT_PRODUCTS_INDEX)
            @inventory_source = pick(inventory_source, "ELEVENST_MISSING_CRAWL_INVENTORY_SOURCE", DEFAULT_INVENTORY_SOURCE)
            @inventory_source_field = pick(
              inventory_source_field,
              "ELEVENST_MISSING_CRAWL_INVENTORY_SOURCE_FIELD",
              "source.keyword",
            )
            @inventory_product_id_field = pick(
              inventory_product_id_field,
              "ELEVENST_MISSING_CRAWL_INVENTORY_PRODUCT_ID_FIELD",
              "source_product_id",
            )
            @products_source = pick(products_source, "ELEVENST_MISSING_CRAWL_PRODUCTS_SOURCE", DEFAULT_PRODUCTS_SOURCE)
            @target_id_template = pick(
              target_id_template,
              "ELEVENST_MISSING_CRAWL_TARGET_ID_TEMPLATE",
              DEFAULT_TARGET_ID_TEMPLATE,
            )
            raw_chunk = bulk_chunk
            raw_chunk = ENV["ELEVENST_MISSING_CRAWL_BULK_CHUNK"].to_s.strip if raw_chunk.nil?
            raw_chunk = DEFAULT_BULK_CHUNK.to_s if raw_chunk.to_s.strip.empty?
            @bulk_chunk = [raw_chunk.to_i, 1].max
            @max_rows = resolve_max_rows(max_rows)
          end

          def fetch
            stats = empty_stats
            buffer = []

            row_loader.each_row do |row|
              buffer << row
              next if buffer.size < @bulk_chunk

              classify_batch!(stats, buffer)
              buffer.clear
              break if @max_rows && stats[:rows].size >= @max_rows
            end

            classify_batch!(stats, buffer) if buffer.any? && (!@max_rows || stats[:rows].size < @max_rows)
            stats[:rows] = stats[:rows].first(@max_rows) if @max_rows
            stats
          rescue StandardError => e
            empty_stats.merge(error: e.message.to_s.byteslice(0, 200))
          end

          private

          def row_loader
            Sources::InventoryRowLoader.new(
              es_client: @es_client,
              index: @inventory_index,
              source_field: @inventory_source_field,
              source_terms: [@inventory_source, @inventory_source.downcase, @inventory_source.upcase].uniq,
              product_id_field: @inventory_product_id_field,
            )
          end

          def classify_batch!(stats, batch)
            resp = @es_client.mget(
              index: @products_index,
              ids: batch.map { |row| target_doc_id(row[:source_product_id]) },
            )
            by_requested_id = {}
            Array(resp["docs"]).each do |doc|
              by_requested_id[doc["_id"].to_s] = doc if doc["found"]
            end

            batch.each do |row|
              stats[:inventory_total] += 1
              doc = by_requested_id[target_doc_id(row[:source_product_id])]
              if doc && source_matches?(doc["_source"])
                stats[:products_found] += 1
                next
              end

              stats[:missing_products] += 1
              stats[:rows] << build_row(row)
            end
          end

          def build_row(row)
            source_product_id = row[:source_product_id].to_s.strip
            inventory_url = row[:source_product_url].to_s.strip
            CrawlRow.new(
              source: row[:source].to_s.strip.empty? ? @inventory_source : row[:source].to_s.strip,
              source_product_id: source_product_id,
              source_product_url: inventory_url.empty? ? nil : inventory_url,
              crawl_url: resolve_crawl_url(source_product_id, inventory_url),
            )
          end

          def resolve_crawl_url(product_id, inventory_url)
            raw = inventory_url.to_s.strip
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

          def target_doc_id(source_product_id)
            format(@target_id_template, id: source_product_id.to_s.strip)
          end

          def pick(cli_value, env_key, default)
            raw = cli_value.to_s.strip
            raw = ENV[env_key].to_s.strip if raw.empty?
            raw.empty? ? default : raw
          end

          def resolve_max_rows(cli_value)
            raw = cli_value.to_s.strip
            raw = ENV["ELEVENST_MISSING_CRAWL_MAX_ROWS"].to_s.strip if raw.empty?
            return nil if raw.empty?

            cap = Integer(raw)
            cap.positive? ? cap : nil
          rescue ArgumentError
            raise EmTools::Core::Errors::ConfigurationError,
              "max-rows must be a positive integer (got #{raw.inspect})"
          end

          def empty_stats
            {
              inventory_index: @inventory_index,
              products_index: @products_index,
              inventory_source: @inventory_source,
              products_source: @products_source,
              inventory_total: 0,
              products_found: 0,
              missing_products: 0,
              rows: [],
            }
          end
        end
      end
    end
  end
end
