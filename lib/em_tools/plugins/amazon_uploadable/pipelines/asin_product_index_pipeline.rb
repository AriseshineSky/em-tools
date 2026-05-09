# frozen_string_literal: true

require 'bigdecimal'
require 'json'
require 'time'

module EmTools
  module Plugins
    module AmazonUploadable
      module Pipelines
        # rubocop:disable Metrics/ClassLength -- single cohesive pipeline; split later if it grows further
        # Streams ASINs from an ASIN Elasticsearch index (via {UploadableProductFilter}), loads product documents
        # by +_id+ from a product API index, resolves a numeric **price** from product +_source+ (configurable dot-paths;
        # lowest-offer index join is not implemented here—extend this class if you need offer-based price), applies
        # filters, and **bulk-indexes** enriched documents into a destination index.
        class AsinProductIndexPipeline
          Stats = Struct.new(
            :asin_hits_seen,
            :asin_ids_collected,
            :products_found,
            :accepted,
            :rejected_no_product,
            :rejected_price,
            :rejected_required_fields,
            :rejected_blacklist,
            :bulk_requests,
            :bulk_errors,
            keyword_init: true
          )

          DEFAULT_PRICE_PATHS = %w[
            price
            list_price
            list_price.amount
            lowest_price
            buybox_price
            amount
          ].freeze

          # rubocop:disable Metrics/ParameterLists -- explicit pipeline knobs; extract Options if this grows further
          def initialize(
            marketplace:,
            sink_index:,
            filter:,
            product_index: nil,
            min_price: nil,
            max_price: nil,
            require_product_fields: [],
            price_field_paths: nil,
            keywords: [],
            title_field: 'title',
            asin_batch_size: 100,
            bulk_chunk_lines: 200,
            max_asin_hits: nil
          )
            @marketplace = marketplace.to_s.downcase.strip
            raise ArgumentError, 'marketplace is required' if @marketplace.empty?

            @sink_index = sink_index.to_s.strip
            raise ArgumentError, 'sink_index is required' if @sink_index.empty?

            @filter = filter
            @product_index = product_index&.to_s&.strip
            if @product_index.nil? || @product_index.empty?
              @product_index = format('amz_products_api_%s_v2',
                                      @marketplace)
            end

            @min_price = min_price.nil? ? nil : BigDecimal(min_price.to_s)
            @max_price = max_price.nil? ? nil : BigDecimal(max_price.to_s)
            @require_fields = Array(require_product_fields).map(&:to_s).map(&:strip).reject(&:empty?)
            @price_paths = (price_field_paths || DEFAULT_PRICE_PATHS).map(&:to_s)
            @keywords = Array(keywords).map { |k| k.to_s.downcase.strip }.reject(&:empty?)
            @title_field = title_field.to_s.strip
            @title_field = 'title' if @title_field.empty?
            @asin_batch_size = [asin_batch_size.to_i, 1].max
            @bulk_chunk_lines = [bulk_chunk_lines.to_i, 1].max
            @max_asin_hits = max_asin_hits&.to_i&.positive? ? max_asin_hits.to_i : nil
          end
          # rubocop:enable Metrics/ParameterLists

          def run!(client:, dry_run: false)
            stats = Stats.new(
              asin_hits_seen: 0,
              asin_ids_collected: 0,
              products_found: 0,
              accepted: 0,
              rejected_no_product: 0,
              rejected_price: 0,
              rejected_required_fields: 0,
              rejected_blacklist: 0,
              bulk_requests: 0,
              bulk_errors: 0
            )

            pending_bulk = []

            flush_bulk = lambda do |pairs|
              return if pairs.empty?
              return if dry_run

              stats.bulk_requests += 1
              resp = bulk_upsert(client, @sink_index, pairs)
              stats.bulk_errors += count_bulk_errors(resp)
            end

            asin_buffer = []

            @filter.each_asin_hit(client: client, batch_size: 500, max_hits: @max_asin_hits) do |hit|
              stats.asin_hits_seen += 1
              asin = asin_from_hit(hit)
              next if asin.empty?

              asin_buffer << asin
              next if asin_buffer.size < @asin_batch_size

              process_buffer(client, asin_buffer, stats, pending_bulk, flush_bulk)
              asin_buffer.clear
            end

            process_buffer(client, asin_buffer, stats, pending_bulk, flush_bulk) if asin_buffer.any?

            flush_bulk.call(pending_bulk) if pending_bulk.any?

            stats
          end

          private

          def asin_from_hit(hit)
            src = hit['_source'] || {}
            (src['asin'] || hit['_id']).to_s.strip.upcase
          end

          def process_buffer(client, asin_buffer, stats, pending_bulk, flush_bulk)
            return if asin_buffer.empty?

            ids = asin_buffer.uniq
            stats.asin_ids_collected += ids.size
            resp = client.mget(index: @product_index, ids: ids)
            docs = resp['docs'] || []

            docs.each_with_index do |doc, idx|
              asin = ids[idx].to_s.strip.upcase
              unless doc['found']
                stats.rejected_no_product += 1
                next
              end

              stats.products_found += 1
              src = doc['_source'] || {}

              if blacklisted_title?(src)
                stats.rejected_blacklist += 1
                next
              end

              unless required_fields_present?(src)
                stats.rejected_required_fields += 1
                next
              end

              price = extract_numeric_price(src)
              unless price_in_range?(price)
                stats.rejected_price += 1
                next
              end

              stats.accepted += 1
              body = build_sink_document(asin, src, price)
              pending_bulk << [asin, body]

              next if pending_bulk.size < @bulk_chunk_lines

              flush_bulk.call(pending_bulk.dup)
              pending_bulk.clear
            end
          end

          def build_sink_document(asin, product_source, price)
            {
              'asin' => asin,
              'marketplace' => @marketplace,
              'product' => product_source,
              'price' => price&.to_f,
              'processed_at' => Time.now.utc.iso8601(3)
            }
          end

          def blacklisted_title?(src)
            return false if @keywords.empty?

            title = (src[@title_field] || src[@title_field.to_sym]).to_s.downcase
            @keywords.any? { |kw| title.include?(kw) }
          end

          def required_fields_present?(src)
            @require_fields.all? do |field|
              v = src[field] || src[field.to_sym]
              v.is_a?(String) ? !v.strip.empty? : !v.nil?
            end
          end

          def extract_numeric_price(src)
            @price_paths.each do |path|
              v = dig_path(src, path)
              n = coerce_number(v)
              return n if n
            end
            nil
          end

          def dig_path(obj, path)
            acc = obj
            path.split('.').each do |key|
              return nil unless acc.is_a?(Hash)

              acc = acc[key] || acc[key.to_sym]
            end
            acc
          end

          def coerce_number(value)
            case value
            when Numeric
              BigDecimal(value.to_s)
            when String
              string_to_bigdecimal(value)
            end
          end

          def string_to_bigdecimal(str)
            s = str.to_s.strip
            return nil if s.empty?

            BigDecimal(s)
          rescue ArgumentError
            nil
          end

          def price_in_range?(price)
            return false if price.nil?

            return false if @min_price && price < @min_price
            return false if @max_price && price > @max_price

            true
          end

          def bulk_upsert(client, sink_index, id_body_pairs)
            chunks = []
            id_body_pairs.each do |id, body|
              chunks << { index: { _index: sink_index, _id: id } }.to_json
              chunks << JSON.generate(body)
            end
            client.bulk(body: "#{chunks.join("\n")}\n")
          end

          def count_bulk_errors(resp)
            return 0 unless resp.is_a?(Hash)

            items = resp['items'] || []
            items.count { |it| it.values.first&.dig('error') }
          end
        end
        # rubocop:enable Metrics/ClassLength
      end
    end
  end
end
