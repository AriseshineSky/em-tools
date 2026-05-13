# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Storefront
      module Cli
        # +em-tools storefront sync-inventory --source SRC ...+ — pull inventory CSVs
        # from the user's Spree storefront for one or more sources, bulk-index into ES,
        # and prune obsolete docs (sync_batch_id older than the latest run).
        class SyncInventory < Dry::CLI::Command
          desc "Sync Spree storefront inventory CSVs into Elasticsearch"

          option :endpoint, desc: "Spree API endpoint (default $EM_TOOLS_SITE_STOREFRONT_ENDPOINT)"
          option :token, desc: "Spree API token (default $EM_TOOLS_SITE_STOREFRONT_TOKEN)"
          option :source,
            type: :array,
            default: [],
            desc: "Inventory source(s) to sync (repeatable / CSV). e.g. AMZ_AE,AMZ_CA"
          option :index, desc: "Override target inventory index (default em_inventory)"
          option :refresh, type: :boolean, default: true, desc: "Refresh index after sync"
          option :prune,
            type: :boolean,
            default: true,
            desc: "Delete docs that no longer exist on the source"

          example [
            "--source AMZ_AE",
            "--source AMZ_AE --source AMZ_CA --no-prune",
            "--source AMZ_AE,Boyner --index custom_inventory",
          ]

          def call(endpoint: nil, token: nil, source: [], index: nil,
            refresh: true, prune: true, **)
            sources = Array(source).flat_map { |s| s.to_s.split(",") }.map(&:strip).reject(&:empty?)
            if sources.empty?
              warn("error: at least one --source is required (e.g. --source AMZ_AE)")
              exit(1)
            end

            site = EmTools::Core::Config.site("storefront")
            resolved_endpoint = endpoint || site["endpoint"]
            resolved_token = token || site["token"]
            if resolved_endpoint.to_s.strip.empty? || resolved_token.to_s.strip.empty?
              warn("error: missing Spree credentials. Set EM_TOOLS_SITE_STOREFRONT_ENDPOINT + " \
                "_TOKEN, or pass --endpoint / --token.")
              exit(2)
            end

            plugin = EmTools::Core::PluginRegistry.fetch(:storefront)
            product_util = plugin.product_util(endpoint: resolved_endpoint, api_key: resolved_token)
            runner_opts = {
              product_util: product_util,
              sources: sources,
              refresh: refresh,
              prune_obsolete: prune,
            }
            runner_opts[:index] = index if index
            results = plugin.sync_inventory(**runner_opts).run!
            print_summary(results)
          end
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

          private

          def print_summary(results)
            puts "Inventory sync results:"
            results.each do |source, info|
              puts format("  %-12s %s bytes=%d %s", source, info[:status], info[:byte_size], info[:error] || "")
            end
          end
        end
      end
    end
  end
end
