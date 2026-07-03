# frozen_string_literal: true

module EmTools
  module Plugins
    module Kr
      module Sources
        # Scroll an inventory index and yield normalized row hashes.
        class InventoryRowLoader
          DEFAULT_SOURCE_FIELDS = %w[
            source
            source_product_id
            source_product_url
            product_url
            url
          ].freeze

          def initialize(
            es_client:,
            index:,
            source_field:,
            source_terms:,
            product_id_field:,
            source_fields: DEFAULT_SOURCE_FIELDS,
            max_hits: nil
          )
            @es_client = es_client
            @index = index.to_s.strip
            @source_field = source_field.to_s.strip
            @source_terms = normalize_source_terms(source_terms)
            @product_id_field = product_id_field.to_s.strip
            @source_fields = Array(source_fields).map(&:to_s).reject(&:empty?)
            @max_hits = resolve_max_hits(max_hits)
          end

          def each_row
            return enum_for(:each_row) unless block_given?

            yielded = 0
            @es_client.iterate_query(
              index: @index,
              query: build_query,
              batch_size: 2_000,
              max_hits: @max_hits,
              _source: @source_fields,
            ) do |hit|
              yielded += 1
              row = normalize_row(hit)
              next if row[:source_product_id].to_s.strip.empty?

              yield row
            end

            warn_max_hits if @max_hits && yielded >= @max_hits
          end

          private

          def resolve_max_hits(max_hits)
            raw = max_hits
            raw = ENV["ELEVENST_MISSING_CRAWL_MAX_HITS"].to_s.strip if raw.nil?
            mh = raw.to_s.empty? ? nil : Integer(raw, exception: false)
            mh&.positive? ? mh : nil
          end

          def warn_max_hits
            warn("InventoryRowLoader: hit ELEVENST_MISSING_CRAWL_MAX_HITS limit; rows may be incomplete.")
          end

          def normalize_source_terms(list)
            arr = Array(list).flat_map { |s| s.to_s.split(",") }.map(&:strip).reject(&:empty?)
            arr.uniq
          end

          def build_query
            {
              bool: {
                filter: [
                  { terms: { @source_field => @source_terms } },
                ],
              },
            }
          end

          def normalize_row(hit)
            src = hit["_source"] || {}
            {
              source: field_value(src, "source"),
              source_product_id: field_value(src, @product_id_field),
              source_product_url: first_present(src, %w[source_product_url product_url url]),
              inventory_doc_id: hit["_id"].to_s,
            }
          end

          def field_value(src, key)
            return src[key] if src.key?(key)
            return src[key.to_sym] if src.key?(key.to_sym)

            nil
          end

          def first_present(src, keys)
            keys.each do |key|
              val = field_value(src, key)
              next if val.nil?

              text = val.to_s.strip
              return text unless text.empty?
            end
            nil
          end
        end
      end
    end
  end
end
