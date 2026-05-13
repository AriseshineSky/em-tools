# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonUploadable
      module Sources
        # Streams ASIN seeds from Elasticsearch using the same query resolution
        # as {Filters::UploadableProductFilter}. The index can be overridden for
        # replay or backfill jobs.
        class EsAsins
          include EmTools::Core::Ports::AsinSource

          DEFAULT_BATCH_SIZE = 500

          def initialize(client:, marketplace:, index: nil, max_asins: nil, filter: nil, **filter_opts)
            @client = client
            @marketplace = marketplace.to_s.downcase.strip
            raise ArgumentError, "marketplace is required" if @marketplace.empty?

            @filter = filter || Filters::UploadableProductFilter.new(marketplace: @marketplace, **filter_opts)
            @index = index.to_s.strip
            @index = @filter.asin_index if @index.empty?
            @max_asins = positive_integer(max_asins)
          end

          def each
            return enum_for(:each) unless block_given?

            @client.iterate_query(
              index: @index,
              query: @filter.asin_query,
              batch_size: DEFAULT_BATCH_SIZE,
              max_hits: @max_asins,
            ) do |hit|
              asin = normalize((hit["_source"] || {})["asin"] || hit["_id"])
              yield asin if valid_asin?(asin)
            end
          end

          def describe
            {
              kind: "es",
              index: @index,
              marketplace: @marketplace,
              max_asins: @max_asins,
              stream: @filter.describe,
            }
          end

          private

          def normalize(value)
            value.to_s.strip.upcase
          end

          def valid_asin?(asin)
            EmTools::Plugins::AmazonLowestOffer::Patterns::AsinPattern.match?(asin)
          end

          def positive_integer(value)
            int = value&.to_i
            int&.positive? ? int : nil
          end
        end
      end
    end
  end
end
