# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Plugins
    module Kr
      module Cli
        class ScheduleStaleInventoryRecrawl < Dry::CLI::Command
          desc "Schedule Scrapyd elevenst recrawl for stale/missing 11ST inventory products"

          option :stale_days,
            aliases: ["-D", "--days"],
            desc: "Recrawl when updated_at is older than N days (default 7)"
          option :time_field,
            default: Queries::StaleInventoryRecrawlQuery::DEFAULT_TIME_FIELD,
            desc: "Product freshness field (default updated_at)"
          option :inventory_index,
            default: Queries::StaleInventoryRecrawlQuery::DEFAULT_INVENTORY_INDEX,
            desc: "Inventory index (default em_inventory)"
          option :products_index,
            default: Queries::StaleInventoryRecrawlQuery::DEFAULT_PRODUCTS_INDEX,
            desc: "Crawled products index (default user1_kr_products)"
          option :inventory_source,
            default: Queries::StaleInventoryRecrawlQuery::DEFAULT_INVENTORY_SOURCE,
            desc: "Inventory source term (default 11ST)"
          option :products_source,
            default: Queries::StaleInventoryRecrawlQuery::DEFAULT_PRODUCTS_SOURCE,
            desc: "Products source value (default elevenst)"
          option :max_urls,
            aliases: ["-n"],
            desc: "Cap URLs scheduled (default unlimited)"
          option :batch_size,
            desc: "URLs per Scrapyd job (default 25)"
          option :dry_run,
            type: :boolean,
            default: false,
            desc: "Only print stale/missing counts; do not call Scrapyd"
          option :data_url,
            aliases: ["--data-url"],
            desc: "Data ES URL (default DATA_ELASTICSEARCH_URL)"
          option :scrapyd_url,
            desc: "Scrapyd base URL (default SCRAPYD_URL)"
          option :scrapyd_project,
            desc: "Scrapyd project (default SCRAPYD_PROJECT)"
          option :scrapyd_username,
            desc: "Scrapyd HTTP basic user (default SCRAPYD_USERNAME)"
          option :scrapyd_password,
            desc: "Scrapyd HTTP basic password (default SCRAPYD_PASSWORD)"

          example [
            "",
            "--stale-days 7",
            "--dry-run",
            "-n 100 --batch-size 20",
          ]

          def call(
            stale_days: nil,
            time_field: Queries::StaleInventoryRecrawlQuery::DEFAULT_TIME_FIELD,
            inventory_index: Queries::StaleInventoryRecrawlQuery::DEFAULT_INVENTORY_INDEX,
            products_index: Queries::StaleInventoryRecrawlQuery::DEFAULT_PRODUCTS_INDEX,
            inventory_source: Queries::StaleInventoryRecrawlQuery::DEFAULT_INVENTORY_SOURCE,
            products_source: Queries::StaleInventoryRecrawlQuery::DEFAULT_PRODUCTS_SOURCE,
            max_urls: nil,
            batch_size: nil,
            dry_run: false,
            data_url: nil,
            scrapyd_url: nil,
            scrapyd_project: nil,
            scrapyd_username: nil,
            scrapyd_password: nil,
            **
          )
            EmTools::Core::Cli::Runner.run do
              plugin = EmTools::Core::PluginRegistry.fetch(:kr)
              result = plugin.schedule_stale_inventory_recrawl(
                data_es_client: build_data_client(data_url),
                scrapyd_client: build_scrapyd_client(
                  scrapyd_url,
                  scrapyd_project,
                  scrapyd_username,
                  scrapyd_password,
                ),
                stale_days: stale_days,
                time_field: time_field,
                inventory_index: inventory_index,
                products_index: products_index,
                inventory_source: inventory_source,
                products_source: products_source,
                max_urls: max_urls,
                batch_size: batch_size,
                dry_run: dry_run,
                logger: plugin.dependencies[:logger],
              ).run!
              $stdout.puts(JSON.generate(summary: result.summary))
              result
            end
          end

          private

          def build_data_client(url)
            resolved = url.to_s.strip
            return EmTools::Core::Config.elasticsearch_client(url: resolved) unless resolved.empty?

            EmTools::Core::Config.elasticsearch_client(cluster: "data")
          end

          def build_scrapyd_client(url, project, username, password)
            EmTools::Clients::ScrapydClient.new(
              url: pick(url, "SCRAPYD_URL"),
              project: pick(project, "SCRAPYD_PROJECT", "kr_products_spider"),
              username: pick(username, "SCRAPYD_USERNAME"),
              password: pick(password, "SCRAPYD_PASSWORD"),
            )
          end

          def pick(cli_value, env_key, default = nil)
            raw = cli_value.to_s.strip
            raw = ENV[env_key].to_s.strip if raw.empty?
            raw = default.to_s if raw.empty? && default
            raw
          end
        end
      end
    end
  end
end
