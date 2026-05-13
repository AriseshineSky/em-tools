# frozen_string_literal: true

module EmTools
  module Plugins
    module Ebay
      # eBay listings coverage pipeline: per-marketplace listings ES query + snapshot writer.
      class Plugin < EmTools::Core::Plugin::Base
        EmTools::Core::PluginRegistry.register(:ebay, self)

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
          }
        end

        def cli_commands
          {
            "listings publish-snapshot" => Cli::PublishSnapshot,
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
