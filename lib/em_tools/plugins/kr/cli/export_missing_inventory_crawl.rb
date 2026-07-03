# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Plugins
    module Kr
      module Cli
        class ExportMissingInventoryCrawl < Dry::CLI::Command
          desc "Export missing 11ST inventory rows (no ES product doc) and optionally schedule Scrapyd"

          option :output,
            aliases: ["-o"],
            desc: "Output TSV path (default log/elevenst-missing-crawl-<timestamp>.tsv)"
          option :inventory_index,
            default: Queries::MissingInventoryCrawlQuery::DEFAULT_INVENTORY_INDEX,
            desc: "Inventory index (default em_inventory)"
          option :products_index,
            default: Queries::MissingInventoryCrawlQuery::DEFAULT_PRODUCTS_INDEX,
            desc: "Crawled products index (default user1_kr_products)"
          option :inventory_source,
            default: Queries::MissingInventoryCrawlQuery::DEFAULT_INVENTORY_SOURCE,
            desc: "Inventory source term (default 11ST)"
          option :products_source,
            default: Queries::MissingInventoryCrawlQuery::DEFAULT_PRODUCTS_SOURCE,
            desc: "Products source value (default elevenst)"
          option :max_rows,
            aliases: ["-n"],
            desc: "Cap exported rows (default unlimited)"
          option :batch_size,
            desc: "URLs per Scrapyd job when --schedule (default 25)"
          option :schedule,
            type: :boolean,
            default: false,
            desc: "Schedule Scrapyd elevenst jobs after export"
          option :dry_run,
            type: :boolean,
            default: false,
            desc: "Export only; with --schedule, print counts without Scrapyd calls"
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
            "-o log/elevenst-missing.tsv",
            "-o log/elevenst-missing.tsv --schedule",
            "-n 500 --schedule --batch-size 25",
          ]

          def call(
            output: nil,
            inventory_index: Queries::MissingInventoryCrawlQuery::DEFAULT_INVENTORY_INDEX,
            products_index: Queries::MissingInventoryCrawlQuery::DEFAULT_PRODUCTS_INDEX,
            inventory_source: Queries::MissingInventoryCrawlQuery::DEFAULT_INVENTORY_SOURCE,
            products_source: Queries::MissingInventoryCrawlQuery::DEFAULT_PRODUCTS_SOURCE,
            max_rows: nil,
            batch_size: nil,
            schedule: false,
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
              result = plugin.export_missing_inventory_crawl(
                data_es_client: build_data_client(data_url),
                scrapyd_client: build_scrapyd_client(
                  scrapyd_url,
                  scrapyd_project,
                  scrapyd_username,
                  scrapyd_password,
                ),
                output_path: output,
                inventory_index: inventory_index,
                products_index: products_index,
                inventory_source: inventory_source,
                products_source: products_source,
                max_rows: max_rows,
                batch_size: batch_size,
                schedule: schedule,
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
