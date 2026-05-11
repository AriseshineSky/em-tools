# frozen_string_literal: true

module EmTools
  module Plugins
    module Ebay
      # eBay listings coverage pipeline: per-marketplace listings ES query + snapshot writer.
      class Plugin < EmTools::Core::Plugin::Base
        EmTools::Core::PluginRegistry.register(:ebay, self)

        def listings_coverage_query(**opts)
          Queries::ListingsCoverageQuery.new(**opts)
        end

        def coverage_snapshot(**opts)
          Sinks::CoverageSnapshot.new(**opts)
        end

        def inventory_product_id_loader(**opts)
          Sources::InventoryProductIdLoader.new(**opts)
        end
      end
    end
  end
end
