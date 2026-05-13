# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonLowestOffer
      # Amazon-side lowest-offer freshness pipeline: GCS seed files -> Elasticsearch coverage
      # snapshot -> coverage assessment queries.
      class Plugin < EmTools::Core::Plugin::Base
        def self.plugin_name = :amazon_lowest_offer

        EmTools::Core::PluginRegistry.register(plugin_name, self)

        def capabilities
          {
            coverage: {
              listings_query: Queries::ListingsCoverageQuery,
              assessment: Queries::CoverageAssessment,
              snapshot: Sinks::CoverageSnapshot,
              publish_snapshot: Pipelines::PublishSnapshot,
              download_and_publish: Pipelines::DownloadAndPublish,
            },
            sources: {
              seed_files: Sources::SeedFiles,
              inventory_asin_loader: Sources::InventoryAsinLoader,
            },
            services: {
              offer_service: Services::OfferService,
            },
            filters: {
              offer_filter: Filters::OfferFilter,
            },
            patterns: {
              asin: Patterns::AsinPattern,
            },
          }
        end

        def dependencies
          @dependencies ||= {
            es_client: EmTools::Clients::ElasticsearchClient.new,
            logger: EmTools::Core::Logger.for(progname: "lowest-offer"),
          }
        end

        def cli_commands
          {
            "coverage publish-snapshot" => Cli::PublishSnapshot,
            "coverage download-and-publish" => Cli::DownloadAndPublish,
          }
        end

        def listings_coverage_query(**opts)
          args = opts.dup
          es_client = args.delete(:es_client) || dependencies[:es_client]
          capabilities.dig(:coverage, :listings_query).new(es_client: es_client, **args)
        end

        def coverage_assessment(**opts)
          args = opts.dup
          search_client = args.delete(:search_client) || dependencies[:es_client]
          capabilities.dig(:coverage, :assessment).new(search_client: search_client, **args)
        end

        def seed_files(**_opts)
          capabilities.dig(:sources, :seed_files)
        end

        def inventory_asin_loader(**opts)
          args = opts.dup
          es_client = args.delete(:es_client) || dependencies[:es_client]
          capabilities.dig(:sources, :inventory_asin_loader).new(es_client: es_client, **args)
        end

        def coverage_snapshot(**_opts)
          capabilities.dig(:coverage, :snapshot)
        end

        def asin_pattern(**_opts)
          capabilities.dig(:patterns, :asin)
        end

        def offer_service(**opts)
          args = opts.dup
          client = args.delete(:client) || dependencies[:es_client]
          capabilities.dig(:services, :offer_service).new(client: client, **args)
        end

        def offer_filter(**opts)
          capabilities.dig(:filters, :offer_filter).new(**opts)
        end

        def publish_snapshot(**opts)
          args = opts.dup
          es_client = args.delete(:es_client) || dependencies[:es_client]
          logger = args.delete(:logger) || dependencies[:logger]
          capabilities.dig(:coverage, :publish_snapshot).new(es_client: es_client, logger: logger, **args)
        end

        def download_and_publish(**opts)
          capabilities.dig(:coverage, :download_and_publish).new(**opts)
        end
      end
    end
  end
end
