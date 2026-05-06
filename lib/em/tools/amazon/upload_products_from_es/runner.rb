# frozen_string_literal: true

require 'logger'

module Em
  module Tools
    module Amazon
      module UploadProductsFromEs
        # Composition root for +em_celery/tools/spree/amz_upload_products_from_es.py+ (+filter_products+).
        #
        # The Python stack wires DB-backed +product_service+, +AmzOfferService+, +PriceCalculator+,
        # and +AmzUploadableProductsFormatter.run+ (rules, pipelines, file exports, secondary ES indices).
        # In this gem we implement the portable slice: ASIN id stream from Elasticsearch (same query as
        # +UploadableProductFilter+), plus config parity for +price.rules.amz_{mp}+ so Ruby callers can
        # grow into a full formatter without reshaping the entrypoint.
        class Runner
          attr_reader :marketplace, :asin_index, :ttl, :config, :logger, :price_rules

          def initialize(marketplace:, index: nil, ttl: 30, config: {}, logger: nil)
            @marketplace = marketplace.to_s.downcase.strip
            raise ArgumentError, 'marketplace is required' if @marketplace.empty?

            @asin_index = resolve_asin_index(index)
            @ttl = ttl.to_i
            @config = config.is_a?(Hash) ? config : {}
            @logger = logger || default_logger
            @price_rules = PriceRules.from_config(@config, marketplace: @marketplace)
          end

          def describe
            {
              marketplace: @marketplace,
              asin_index: @asin_index,
              ttl: @ttl,
              price_rules: @price_rules.to_h,
              implemented: {
                asin_elasticsearch_stream: true,
                product_service: false,
                offer_service: false,
                price_calculator_pipelines: false,
                formatter_run_file_outputs: false
              },
              stream: build_filter.describe
            }
          end

          def run!(client:, io: $stdout, max_asins: nil)
            @logger.info(
              "Start uploadable-products formatting marketplace=#{@marketplace} index=#{@asin_index} ttl=#{@ttl}"
            )
            build_filter.stream_asins!(client: client, io: io, max_asins: max_asins)
            @logger.info(
              "Completed uploadable-products formatting marketplace=#{@marketplace} index=#{@asin_index}"
            )
          rescue StandardError => e
            @logger.error(
              "Failed uploadable-products formatting marketplace=#{@marketplace} " \
              "index=#{@asin_index}: #{e.class}: #{e.message}"
            )
            raise
          end

          private

          def resolve_asin_index(override)
            return override.to_s.strip if override && !override.to_s.strip.empty?

            "amz_asins_#{@marketplace}"
          end

          def build_filter
            UploadableProductFilter.new(
              marketplace: @marketplace,
              index: @asin_index,
              ttl: @ttl,
              config: @config
            )
          end

          def default_logger
            ::Logger.new($stderr, progname: 'em-tools', level: ::Logger::INFO)
          end
        end
      end
    end
  end
end
