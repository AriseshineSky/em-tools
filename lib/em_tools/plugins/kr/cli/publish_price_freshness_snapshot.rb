# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Plugins
    module Kr
      module Cli
        class PublishPriceFreshnessSnapshot < Dry::CLI::Command
          desc "Publish 11ST price freshness snapshot (inventory vs user1_kr_products) to monitoring ES"

          option :threshold_days,
            aliases: ["-D", "--days"],
            desc: "Fresh threshold in days (default 7; override via ELEVENST_PRICE_FRESHNESS_THRESHOLD_DAYS)"
          option :time_field,
            default: Queries::PriceFreshnessQuery::DEFAULT_TIME_FIELD,
            desc: "Product timestamp field for price freshness (default date)"
          option :inventory_index,
            default: Queries::PriceFreshnessQuery::DEFAULT_INVENTORY_INDEX,
            desc: "Inventory index (default em_inventory)"
          option :products_index,
            default: Queries::PriceFreshnessQuery::DEFAULT_PRODUCTS_INDEX,
            desc: "Crawled products index (default user1_kr_products)"
          option :inventory_source,
            default: Queries::PriceFreshnessQuery::DEFAULT_INVENTORY_SOURCE,
            desc: "Inventory source term (default 11ST)"
          option :products_source,
            default: Queries::PriceFreshnessQuery::DEFAULT_PRODUCTS_SOURCE,
            desc: "Products source value (default elevenst)"
          option :target_id_template,
            default: Queries::PriceFreshnessQuery::DEFAULT_TARGET_ID_TEMPLATE,
            desc: "Map inventory source_product_id to ES _id (default elevenst_%<id>s)"
          option :data_url,
            aliases: ["--data-url"],
            desc: "Data ES URL (default DATA_ELASTICSEARCH_URL)"
          option :target_url,
            aliases: ["--target-url"],
            desc: "Monitoring ES URL (default ELASTICSEARCH_URL)"

          example [
            "",
            "--threshold-days 7",
            "-D 14 --time-field date",
          ]

          def call(
            threshold_days: nil,
            time_field: Queries::PriceFreshnessQuery::DEFAULT_TIME_FIELD,
            inventory_index: Queries::PriceFreshnessQuery::DEFAULT_INVENTORY_INDEX,
            products_index: Queries::PriceFreshnessQuery::DEFAULT_PRODUCTS_INDEX,
            inventory_source: Queries::PriceFreshnessQuery::DEFAULT_INVENTORY_SOURCE,
            products_source: Queries::PriceFreshnessQuery::DEFAULT_PRODUCTS_SOURCE,
            target_id_template: Queries::PriceFreshnessQuery::DEFAULT_TARGET_ID_TEMPLATE,
            data_url: nil,
            target_url: nil,
            **
          )
            EmTools::Core::Cli::Runner.run do
              plugin = EmTools::Core::PluginRegistry.fetch(:kr)
              result = plugin.publish_price_freshness_snapshot(
                data_es_client: build_client(data_url, cluster: "data"),
                es_client: build_client(target_url, cluster: "primary"),
                threshold_days: threshold_days,
                time_field: time_field,
                inventory_index: inventory_index,
                products_index: products_index,
                inventory_source: inventory_source,
                products_source: products_source,
                target_id_template: target_id_template,
                logger: plugin.dependencies[:logger],
              ).run!
              $stdout.puts(JSON.generate(summary: result.summary))
              result
            end
          end

          private

          def build_client(url, cluster:)
            resolved = url.to_s.strip
            return EmTools::Core::Config.elasticsearch_client(url: resolved) unless resolved.empty?

            EmTools::Core::Config.elasticsearch_client(cluster: cluster)
          end
        end
      end
    end
  end
end
