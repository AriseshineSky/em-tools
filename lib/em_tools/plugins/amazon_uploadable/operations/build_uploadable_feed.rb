# frozen_string_literal: true

require "json"
require "time"

module EmTools
  module Plugins
    module AmazonUploadable
      module Operations
        # Builds Amazon uploadable feed rows from an ASIN source and writes them
        # to one or more sinks. Sources and sinks are injected so the operation
        # can run ES->ES, ES->file, file->ES, or file->file without branching.
        class BuildUploadableFeed
          Stats = Struct.new(
            :asin_count,
            :product_count,
            :emitted_count,
            :no_info_count,
            :no_offer_count,
            :invalid_offer_count,
            keyword_init: true,
          )

          DEFAULT_BATCH_SIZE = 500

          def initialize(marketplace:, source:, sink:, client:,
            listing_source: nil, source_code: nil, store_code: nil, export: false,
            ttl: 30, product_index: nil, offer_index: nil, skip_offers: false,
            product_price_field: "price", product_currency_field: "currency",
            offer_price_field: nil, offer_currency_field: nil, batch_size: DEFAULT_BATCH_SIZE,
            dry_run: false, logger: nil)
            @marketplace = normalize_marketplace(marketplace)
            @source = source
            @sink = sink
            @client = client
            @listing_source = blank?(listing_source) ? "AMZ_#{@marketplace.upcase}" : listing_source.to_s
            @source_code = source_code.to_s
            @store_code = store_code&.to_s
            @export = export ? true : false
            @ttl = ttl.to_i
            @product_index = resolve_index(product_index, "amz_products_api_#{@marketplace}_v2")
            @offer_index = resolve_index(offer_index, "lowest_offer_listings_#{@marketplace}_new")
            @skip_offers = skip_offers ? true : false
            @product_price_field = product_price_field.to_s
            @product_currency_field = product_currency_field.to_s
            @offer_price_field = (offer_price_field || ENV.fetch("FORMAT_FROM_FILE_OFFER_PRICE_FIELD", "price")).to_s
            @offer_currency_field = (offer_currency_field || ENV.fetch("FORMAT_FROM_FILE_OFFER_CURRENCY_FIELD", "currency")).to_s
            @batch_size = [batch_size.to_i, 1].max
            @dry_run = dry_run ? true : false
            @logger = logger || EmTools::Core::Logger.for(progname: "amz-build-feed")
            @stats = new_stats
          end

          def describe
            {
              marketplace: @marketplace,
              product_index: @product_index,
              offer_index: @offer_index,
              skip_offers: @skip_offers,
              listing_source: @listing_source,
              source_code: @source_code,
              store_code: @store_code,
              export: @export,
              ttl: @ttl,
              batch_size: @batch_size,
              source: describe_part(@source),
              sink: describe_part(@sink),
            }
          end

          def run!
            return describe if @dry_run

            @logger.info("Start build uploadable feed marketplace=#{@marketplace}")
            each_asin_batch { |batch| process_batch(batch) }
            result = @stats.to_h.merge(@sink.stats)
            @logger.info("Completed build uploadable feed marketplace=#{@marketplace} stats=#{result.inspect}")
            result
          ensure
            @sink&.close unless @dry_run
          end

          private

          def each_asin_batch
            buf = []
            @source.each do |asin|
              normalized = asin.to_s.strip.upcase
              next if normalized.empty?

              buf << normalized
              next if buf.size < @batch_size

              yield buf
              buf = []
            end
            yield buf if buf.any?
          end

          def process_batch(batch)
            ids = batch.uniq
            @stats.asin_count += ids.size
            products = index_mget_docs(@client.mget(index: @product_index, ids: ids))
            offers = load_offers(ids)
            ids.each { |asin| emit_row(asin, products[asin], offers[asin]) }
          end

          def load_offers(ids)
            return {} if @skip_offers || !@client.index_exists?(@offer_index)

            index_mget_docs(@client.mget(index: @offer_index, ids: ids))
          end

          def emit_row(asin, product_doc, offer_doc)
            unless product_doc && product_doc["found"]
              @stats.no_info_count += 1
              return
            end

            @stats.product_count += 1
            src = product_doc["_source"] || {}
            state, price, currency = extract_offer(offer_doc, product_src: src)
            case state
            when :no_offer
              @stats.no_offer_count += 1
              return
            when :invalid_offer
              @stats.invalid_offer_count += 1
              return
            end

            @sink.index(build_row(asin, src, price, currency))
            @stats.emitted_count += 1
          end

          def build_row(asin, product_src, price, currency)
            row = Transforms::ListingProductShape.from_es_product(
              product_src,
              marketplace: @marketplace,
              cli_source: @listing_source,
              cli_source_code: @source_code,
            )
            row["store_code"] = @store_code if @store_code
            row["export"] = @export
            row["ttl_days"] = @ttl
            row["price"] = price
            row["currency"] = currency
            row["shipping_days_min"] = nil
            row["shipping_days_max"] = nil
            row["processed_at"] = Time.now.utc.iso8601(3)
            row["asin"] = asin
            row
          end

          def extract_offer(doc, product_src:)
            return offer_from_product_source(product_src) if @skip_offers
            return [:no_offer, nil, nil] if doc.nil? || doc["found"] == false

            src = doc["_source"] || {}
            price_raw = Transforms::ListingProductShape.pick(src, @offer_price_field)
            cur = Transforms::ListingProductShape.pick(src, @offer_currency_field) || "USD"
            coerce_price_state(price_raw, cur)
          end

          def offer_from_product_source(product_src)
            price_raw = Transforms::ListingProductShape.pick(product_src, @product_price_field)
            cur = Transforms::ListingProductShape.pick(product_src, @product_currency_field) || "USD"
            coerce_price_state(price_raw, cur)
          end

          def coerce_price_state(price_raw, currency)
            blank = price_raw.nil? || (price_raw.is_a?(String) && price_raw.strip.empty?)
            return [:invalid_offer, nil, nil] if blank

            [:ok, price_raw.is_a?(Numeric) ? price_raw.to_f : Float(price_raw), currency.to_s]
          rescue ArgumentError, TypeError
            [:invalid_offer, nil, nil]
          end

          def index_mget_docs(resp)
            docs = resp["docs"] || []
            docs.each_with_object({}) do |doc, out|
              id = (doc["_id"] || doc[:_id]).to_s.strip.upcase
              out[id] = doc
            end
          end

          def normalize_marketplace(value)
            mp = value.to_s.downcase.strip
            raise ArgumentError, "marketplace is required" if mp.empty?

            mp
          end

          def resolve_index(value, fallback)
            name = value.to_s.strip
            name.empty? ? fallback : name
          end

          def blank?(value)
            value.nil? || value.to_s.strip.empty?
          end

          def describe_part(part)
            part.respond_to?(:describe) ? part.describe : { kind: part.class.name }
          end

          def new_stats
            Stats.new(
              asin_count: 0,
              product_count: 0,
              emitted_count: 0,
              no_info_count: 0,
              no_offer_count: 0,
              invalid_offer_count: 0,
            )
          end
        end
      end
    end
  end
end
