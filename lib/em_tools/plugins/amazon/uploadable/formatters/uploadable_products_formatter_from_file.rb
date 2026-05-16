# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Formatters
          # Ruby port of +em_celery/tools/spree/amz_uploadable_products_formatter_from_file.py+ driving
          # +em_tasks.tools.amz_uploadable_products_formatter.AmzUploadableProductsFormatter+ (file-based path).
          #
          # Python flow (active code today, with many filters/pipelines commented in em-tasks):
          # 1. Read ASINs (one per line) from +products_path+.
          # 2. Batch load product payloads from Elasticsearch (+amz_products_api_<mp>_v2+ via product_service+ in Python).
          # 3. Batch fetch offers (+offer_service.get_offers+ in Python); merge +price+ / +currency+ onto converted product.
          # 4. Write one JSON object per line to +output_path+ (+shipping_days_min/max+ set null).
          # 5. Append +record_messages.txt+ and write sidecar ASIN list files under +emitter_dir+.
          #
          # This implementation uses +ElasticsearchClient#mget+ for products and offers (no DB / no RPC).
          # Offer documents are expected in +offer_index+ (default +lowest_offer_listings_<mp>_new+) with +_id+ = ASIN
          # and price fields configurable (+offer_price_field+, +offer_currency_field+). # -- mirrors Python formatter surface (paths, indices, counters, batch loop).
          class UploadableProductsFormatterFromFile
            attr_reader :marketplace, :products_path, :output_path, :emitter_dir, :sink_index, :record

            DEFAULT_SINK_BULK_CHUNK_LINES = 500

            def initialize(
              marketplace:,
              products_path:,
              source:,
              source_code:,
              output_path: nil,
              store_code: nil,
              export: false,
              ttl: 30,
              product_index: nil,
              offer_index: nil,
              emitter_dir: nil,
              offer_price_field: nil,
              offer_currency_field: nil,
              batch_size: 500,
              skip_offers: false,
              product_price_field: "price",
              product_currency_field: "currency",
              sink_index: nil,
              sink_bulk_chunk_lines: DEFAULT_SINK_BULK_CHUNK_LINES,
              sink_refresh: false,
              dry_run: false
            )
              @marketplace = marketplace.to_s.downcase.strip
              raise ArgumentError, "marketplace is required" if @marketplace.empty?

              @products_path = File.expand_path(products_path.to_s)
              out_str = output_path.to_s.strip
              @output_path = out_str.empty? ? nil : File.expand_path(out_str)
              @source = source.to_s
              @source_code = source_code.to_s
              @store_code = store_code&.to_s
              @export = export ? true : false
              @ttl = ttl.to_i
              @product_index = product_index&.to_s&.strip
              @product_index = "amz_products_api_#{@marketplace}_v2" if @product_index.nil? || @product_index.empty?
              @offer_index = offer_index&.to_s&.strip
              @offer_index = "lowest_offer_listings_#{@marketplace}_new" if @offer_index.nil? || @offer_index.empty?
              @emitter_dir = emitter_dir&.to_s&.strip
              if @emitter_dir.to_s.empty?
                @emitter_dir = File.expand_path(File.join(Dir.home, ".em_tasks", "amz_#{@marketplace}"))
              end
              @offer_price_field = (offer_price_field || ENV.fetch("FORMAT_FROM_FILE_OFFER_PRICE_FIELD", "price")).to_s
              cur_env = ENV.fetch("FORMAT_FROM_FILE_OFFER_CURRENCY_FIELD", "currency")
              @offer_currency_field = (offer_currency_field || cur_env).to_s
              @batch_size = [batch_size.to_i, 1].max
              @skip_offers = skip_offers
              @product_price_field = product_price_field.to_s
              @product_currency_field = product_currency_field.to_s

              sink_str = sink_index.to_s.strip
              @sink_index = sink_str.empty? ? nil : sink_str
              @sink_bulk_chunk = [sink_bulk_chunk_lines.to_i, 1].max
              @sink_refresh = sink_refresh ? true : false
              @dry_run = dry_run ? true : false
              raise ArgumentError, "either output_path or sink_index must be set" if @output_path.nil? && @sink_index.nil?

              @no_offer = {}
              @invalid_offer = {}
              @no_info = {}
              @offer_except = {}
              @record = {
                "asin_count" => 0,
                "blacklist_asin_count" => 0,
                "no_price_asin_count" => 0,
                "pipeline_filtered_asin_count" => 0,
                "offer_except_asin_count" => 0,
                "no_offer_asin_count" => 0,
                "invalid_offer_asin_count" => 0,
                "unuploadable_asin_count" => 0,
                "filtered_asin_count" => 0,
                "uploaded_asin_count" => 0,
                "product_count" => 0,
                "expired_offer_asins_count" => 0,
                "to_check_offer" => 0,
                "es_bulk_requests" => 0,
                "es_bulk_errors" => 0,
                "es_indexed_count" => 0,
              }
            end
            # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

            def run!(client:)
              prepare_run!(client)
              with_output_file do |out|
                each_asin_batch { |batch| process_batch(client, batch, out) }
                flush_sink_buffer!
              end
              @client.refresh(@sink_index) if @sink_index && @sink_refresh && !@dry_run
              persist_sidecars
            end

            private

            def prepare_run!(client)
              raise "products file not found: #{@products_path}" unless File.file?(@products_path)

              FileUtils.mkdir_p(File.dirname(@output_path)) if @output_path
              FileUtils.mkdir_p(@emitter_dir)
              @client = client
              @sink_buffer = []
            end

            def with_output_file(&block)
              if @output_path
                File.open(@output_path, "w", encoding: "utf-8", &block)
              else
                block.call(nil)
              end
            end

            def each_asin_batch
              buf = []
              File.foreach(@products_path, encoding: "utf-8") do |line|
                id = line.strip
                next if id.empty?

                buf << id.upcase
                next if buf.size < @batch_size

                yield buf
                buf = []
              end
              yield buf if buf.any?
            end

            def process_batch(client, batch, out)
              @record["asin_count"] += batch.size
              prod_by_idx = index_mget_docs(client.mget(index: @product_index, ids: batch))
              offer_by_idx = load_offer_index(client, batch)
              batch.each { |asin| emit_product_line(asin, prod_by_idx, offer_by_idx, out) }
            end

            def load_offer_index(client, batch)
              return {} if @skip_offers || !client.index_exists?(@offer_index)

              index_mget_docs(client.mget(index: @offer_index, ids: batch))
            end

            # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
            def emit_product_line(asin, prod_by_idx, offer_by_idx, out)
              pdoc = prod_by_idx[asin]
              unless pdoc && pdoc["found"]
                @no_info[asin] = true
                return
              end

              @record["product_count"] += 1
              src = pdoc["_source"] || {}
              row = Transforms::ListingProductShape.from_es_product(
                src,
                marketplace: @marketplace,
                cli_source: @source,
                cli_source_code: @source_code,
              )
              row["store_code"] = @store_code if @store_code
              row["export"] = @export
              row["ttl_days"] = @ttl

              state, price, currency = extract_offer(offer_by_idx[asin], product_src: src)
              case state
              when :no_offer
                @no_offer[asin] = true
                return
              when :invalid_offer
                @invalid_offer[asin] = true
                return
              end

              row["price"] = price
              row["currency"] = currency
              row["shipping_days_min"] = nil
              row["shipping_days_max"] = nil

              @record["to_check_offer"] += 1
              emit_row(asin, row, out)
            end
            # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

            def emit_row(asin, row, out)
              out&.puts(JSON.generate(row))
              return unless @sink_index

              @sink_buffer << [asin, row]
              flush_sink_buffer! if @sink_buffer.size >= @sink_bulk_chunk
            end

            def flush_sink_buffer!
              return unless @sink_index
              return if @sink_buffer.empty?

              unless @dry_run
                @record["es_bulk_requests"] += 1
                resp = bulk_index_documents(@client, @sink_index, @sink_buffer)
                @record["es_bulk_errors"] += count_bulk_errors(resp)
              end

              @record["es_indexed_count"] += @sink_buffer.size
              @sink_buffer.clear
            end

            def bulk_index_documents(client, sink_index, id_body_pairs)
              chunks = []
              id_body_pairs.each do |id, body|
                chunks << JSON.generate(index: { _index: sink_index, _id: id })
                chunks << JSON.generate(body)
              end
              client.bulk(body: "#{chunks.join("\n")}\n")
            end

            def count_bulk_errors(resp)
              return 0 unless resp.is_a?(Hash)

              items = resp["items"] || []
              items.count { |it| it.values.first&.dig("error") }
            end

            def index_mget_docs(resp)
              docs = resp["docs"] || []
              out = {}
              docs.each do |d|
                id = (d["_id"] || d[:_id]).to_s.strip.upcase
                out[id] = d
              end
              out
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

              price = price_raw.is_a?(Numeric) ? price_raw.to_f : Float(price_raw)
              [:ok, price, currency.to_s]
            rescue ArgumentError, TypeError
              [:invalid_offer, nil, nil]
            end

            def persist_sidecars
              sync_record_counts!
              append_record_message!
              write_asin_sidecar_files!
            end

            def sync_record_counts!
              @record["invalid_offer_asin_count"] = @invalid_offer.size
              @record["no_offer_asin_count"] = @no_offer.size
              @record["offer_except_asin_count"] = @offer_except.size
            end

            def append_record_message!
              path = File.join(@emitter_dir, "record_messages.txt")
              write_lines(path, [@record.to_json], append: true)
            end

            def write_asin_sidecar_files!
              write_lines(File.join(@emitter_dir, "no_offer_asins.txt"), @no_offer.keys)
              write_lines(File.join(@emitter_dir, "invalid_offer_asins.txt"), @invalid_offer.keys)
              write_lines(File.join(@emitter_dir, "no_info_products.txt"), @no_info.keys)
              return if @offer_except.none?

              write_lines(File.join(@emitter_dir, "offer_except_asins.txt"), @offer_except.keys)
            end

            def write_lines(path, lines, append: false)
              mode = append ? "a" : "w"
              File.open(path, mode, encoding: "utf-8") do |f|
                lines.each { |ln| f.puts(ln) }
              end
            end
          end
          # rubocop:enable Metrics/ClassLength
        end
      end
    end
  end
end
