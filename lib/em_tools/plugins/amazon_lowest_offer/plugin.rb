# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonLowestOffer
      # Amazon-side lowest-offer freshness pipeline: GCS seed files -> Elasticsearch coverage
      # snapshot -> coverage assessment queries.
      class Plugin < EmTools::Core::Plugin::Base
        EmTools::Core::PluginRegistry.register(:amazon_lowest_offer, self)

        def listings_coverage_query(**opts)
          Queries::ListingsCoverageQuery.new(**opts)
        end

        def coverage_assessment(**opts)
          Queries::CoverageAssessment.new(**opts)
        end

        def seed_files(**opts)
          Sources::SeedFiles.new(**opts)
        end

        def inventory_asin_loader(**opts)
          Sources::InventoryAsinLoader.new(**opts)
        end

        def coverage_snapshot(**opts)
          Sinks::CoverageSnapshot.new(**opts)
        end

        def asin_pattern(**opts)
          Patterns::AsinPattern.new(**opts)
        end

        def offer_service(**opts)
          Services::OfferService.new(**opts)
        end

        def offer_filter(**opts)
          Filters::OfferFilter.new(**opts)
        end
      end
    end
  end
end
