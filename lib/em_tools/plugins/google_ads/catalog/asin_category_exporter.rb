# frozen_string_literal: true

require "csv"
require "fileutils"

module EmTools
  module Plugins
    module GoogleAds
      module Catalog
        # Looks up each ASIN in +amz_products_api_<mp>_v2+ (document _id = ASIN) and exports the
        # first entry of the +categories+ array (+cat_id+, +cat_name+).
        class AsinCategoryExporter
          MGET_BATCH = 500
          DEFAULT_MARKETPLACE = "de"

          def initialize(es_client:, product_index:, logger: nil)
            @es = es_client
            @product_index = product_index.to_s.strip
            @logger = logger || EmTools::Core::Logger.for(progname: "google-ads-catalog")
          end

          # @param input_path [String] local ASIN list (from +missing-product-ids+)
          # @param output_path [String] TSV path: asin, cat_id, cat_name
          # @return [Hash] summary counts
          def export!(input_path:, output_path:)
            raise ArgumentError, "product_index is required" if @product_index.empty?

            unless @es.index_exists?(@product_index)
              raise EmTools::Core::Errors::ConfigurationError,
                "Elasticsearch index not found: #{@product_index}"
            end

            asins = AsinListReader.read!(input_path)
            rows = []
            found = missing = no_category = 0

            asins.each_slice(MGET_BATCH) do |batch|
              resp = @es.mget(index: @product_index, ids: batch)
              Array(resp["docs"]).each do |doc|
                asin = doc["_id"].to_s
                unless doc["found"]
                  missing += 1
                  rows << [asin, nil, nil, "not_found"]
                  next
                end

                cat = first_category(doc["_source"])
                if cat.nil?
                  no_category += 1
                  rows << [asin, nil, nil, "no_category"]
                  next
                end

                found += 1
                rows << [asin, cat[:cat_id], cat[:cat_name], "ok"]
              end
            end

            path = File.expand_path(output_path)
            FileUtils.mkdir_p(File.dirname(path))
            write_tsv(path, rows)

            summary = {
              input_path: File.expand_path(input_path),
              product_index: @product_index,
              asins: asins.size,
              found: found,
              missing: missing,
              no_category: no_category,
              output_path: path,
            }
            @logger.info { summary.map { |k, v| "#{k}=#{v}" }.join(" ") }
            summary
          end

          # @param marketplace [String] e.g. +"de"+ → +amz_products_api_de_v2+
          def self.index_for_marketplace(marketplace)
            mp = marketplace.to_s.strip.downcase
            raise ArgumentError, "marketplace is required" if mp.empty?

            "amz_products_api_#{mp}_v2"
          end

          private

          def first_category(source)
            return unless source.is_a?(Hash)

            cats = source["categories"] || source[:categories]
            return unless cats.is_a?(Array) && cats.any?

            c = cats.first
            return unless c.is_a?(Hash)

            name = c["cat_name"] || c[:cat_name]
            id = c["cat_id"] || c[:cat_id]
            return if name.to_s.strip.empty? && id.to_s.strip.empty?

            { cat_id: id.to_s, cat_name: name.to_s }
          end

          def write_tsv(path, rows)
            CSV.open(path, "wb", col_sep: "\t", force_quotes: false) do |csv|
              csv << %w[asin cat_id cat_name status]
              rows.each { |row| csv << row }
            end
          end
        end
      end
    end
  end
end
