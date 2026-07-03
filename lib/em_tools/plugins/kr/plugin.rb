# frozen_string_literal: true

module EmTools
  module Plugins
    module Kr
      # Korean marketplace monitoring (11ST / elevenst price freshness).
      class Plugin < EmTools::Core::Plugin::Base
        def self.plugin_name = :kr

        EmTools::Core::PluginRegistry.register(plugin_name, self)

        def capabilities
          {
            price_freshness: {
              query: Queries::PriceFreshnessQuery,
              snapshot: Sinks::PriceFreshnessSnapshot,
              publish_snapshot: Pipelines::PublishPriceFreshnessSnapshot,
            },
          }
        end

        def dependencies
          @dependencies ||= {
            data_es_client: EmTools::Core::Config.elasticsearch_client(cluster: "data"),
            es_client: EmTools::Clients::ElasticsearchClient.new,
            logger: EmTools::Core::Logger.for(progname: "kr"),
          }
        end

        def cli_commands
          {
            "elevenst publish-price-freshness-snapshot" => Cli::PublishPriceFreshnessSnapshot,
            "elevenst schedule-stale-recrawl" => Cli::ScheduleStaleInventoryRecrawl,
            "elevenst export-missing-crawl" => Cli::ExportMissingInventoryCrawl,
          }
        end

        def price_freshness_query(**opts)
          args = opts.dup
          es_client = args.delete(:es_client) || dependencies[:data_es_client]
          capabilities.dig(:price_freshness, :query).new(es_client: es_client, **args)
        end

        def price_freshness_snapshot(**_opts)
          capabilities.dig(:price_freshness, :snapshot)
        end

        def publish_price_freshness_snapshot(**opts)
          args = opts.dup
          data_es_client = args.delete(:data_es_client) || dependencies[:data_es_client]
          es_client = args.delete(:es_client) || dependencies[:es_client]
          logger = args.delete(:logger) || dependencies[:logger]
          capabilities.dig(:price_freshness, :publish_snapshot).new(
            data_es_client: data_es_client,
            es_client: es_client,
            logger: logger,
            **args,
          )
        end

        def schedule_stale_inventory_recrawl(**opts)
          args = opts.dup
          data_es_client = args.delete(:data_es_client) || dependencies[:data_es_client]
          scrapyd_client = args.delete(:scrapyd_client)
          logger = args.delete(:logger) || dependencies[:logger]
          Pipelines::ScheduleStaleInventoryRecrawl.new(
            data_es_client: data_es_client,
            scrapyd_client: scrapyd_client,
            logger: logger,
            **args,
          )
        end

        def export_missing_inventory_crawl(**opts)
          args = opts.dup
          data_es_client = args.delete(:data_es_client) || dependencies[:data_es_client]
          scrapyd_client = args.delete(:scrapyd_client)
          logger = args.delete(:logger) || dependencies[:logger]
          Pipelines::ExportMissingInventoryCrawl.new(
            data_es_client: data_es_client,
            scrapyd_client: scrapyd_client,
            logger: logger,
            **args,
          )
        end
      end
    end
  end
end
