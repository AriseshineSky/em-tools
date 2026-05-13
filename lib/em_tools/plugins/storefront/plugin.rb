# frozen_string_literal: true

module EmTools
  module Plugins
    module Storefront
      # User-owned storefront (Spree-derived). Source/sink for product / inventory / offer data
      # consumed by other plugins; exposes the +product-importer+ CLI for filtering local CSV /
      # JSON product feeds against the rule engine.
      class Plugin < EmTools::Core::Plugin::Base
        def self.plugin_name = :storefront

        EmTools::Core::PluginRegistry.register(plugin_name, self)

        def capabilities
          {
            products: {
              importer: Importers::ProductImporter,
            },
            inventory: {
              sync: Runners::SyncInventory,
            },
            moderation: {
              unpublish_candidates: Runners::UnpublishCandidates,
            },
            helpers: {
              product_util: ProductUtil,
            },
          }
        end

        def dependencies
          @dependencies ||= {
            site: EmTools::Core::Config.site("storefront"),
            es_client: EmTools::Clients::ElasticsearchClient.new,
          }
        end

        def cli_commands
          {
            "import-products" => Cli::ImportProducts,
            "sync-inventory" => Cli::SyncInventory,
            "unpublish-candidates" => Cli::UnpublishCandidates,
          }
        end

        def product_util(endpoint: dependencies[:site]["endpoint"], api_key: dependencies[:site]["token"], **opts)
          capabilities.dig(:helpers, :product_util).new(endpoint, api_key, **opts)
        end

        def product_importer(**opts)
          capabilities.dig(:products, :importer).new(**opts)
        end

        def sync_inventory(product_util: nil, sink: nil, **opts)
          args = opts.dup
          product_util ||= self.product_util(logger: args[:logger])
          sink ||= EmTools::Core::Sinks::ElasticsearchBulkSink.new
          capabilities.dig(:inventory, :sync).new(product_util: product_util, sink: sink, **args)
        end

        def unpublish_candidates(es_client: dependencies[:es_client], **opts)
          args = opts.dup
          default_es_client = es_client
          client = args.delete(:es_client) || default_es_client
          capabilities.dig(:moderation, :unpublish_candidates).new(es_client: client, **args)
        end
      end
    end
  end
end
