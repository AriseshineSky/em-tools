# frozen_string_literal: true

module EmTools
  module Plugins
    module Ebay
      # eBay listings coverage pipeline: per-marketplace listings ES query + snapshot writer.
      class Plugin < EmTools::Core::Plugin::Base
        def self.plugin_name = :ebay

        EmTools::Core::PluginRegistry.register(plugin_name, self)

        def capabilities
          {
            listings: {
              coverage_query: Queries::ListingsCoverageQuery,
              coverage_snapshot: Sinks::CoverageSnapshot,
              inventory_product_id_loader: Sources::InventoryProductIdLoader,
              publish_snapshot: Pipelines::PublishSnapshot,
            },
          }
        end

        def dependencies
          @dependencies ||= {
            es_client: EmTools::Clients::ElasticsearchClient.new,
            logger: EmTools::Core::Logger.for(progname: "ebay"),
          }
        end

        def cli_commands
          {
            "listings publish-snapshot" => Cli::PublishSnapshot,
            "products export-redirect-product-ids" => Cli::ExportRedirectProductIds,
            "products export-nonexistent-product-ids" => Cli::ExportNonexistentProductIds,
            "products sync-user1" => ProductSync::Cli::SyncUser1Products,
            "products analyze-user1-cn-categories" => ProductSync::Cli::AnalyzeUser1CnCategories,
            "inventory lookup-product-ids" => Cli::LookupInventoryProductIds,
          }
        end

        def listings_coverage_query(**opts)
          args = opts.dup
          es_client = args.delete(:es_client) || dependencies[:es_client]
          capabilities.dig(:listings, :coverage_query).new(es_client: es_client, **args)
        end

        def coverage_snapshot(**_opts)
          capabilities.dig(:listings, :coverage_snapshot)
        end

        def inventory_product_id_loader(**opts)
          args = opts.dup
          es_client = args.delete(:es_client) || dependencies[:es_client]
          capabilities.dig(:listings, :inventory_product_id_loader).new(es_client: es_client, **args)
        end

        def publish_snapshot(**opts)
          args = opts.dup
          es_client = args.delete(:es_client) || dependencies[:es_client]
          capabilities.dig(:listings, :publish_snapshot).new(es_client: es_client, **args)
        end
      end
    end
  end
end
