# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Plugins
    module Storefront
      module Cli
        # +em-tools storefront unpublish-candidates+ — iterate +em_inventory+, run the
        # rule registry against the matching Amazon-side product doc, and bulk-index
        # failing ASINs into +em_products_to_unpublish+.
        class UnpublishCandidates < Dry::CLI::Command
          desc "Flag inventory rows whose Amazon product doc fails any rule"

          option :inventory_index,
            default: "em_inventory",
            desc: "Source ES index (default em_inventory)"
          option :unpublish_index,
            default: "em_products_to_unpublish",
            desc: "Target ES index (default em_products_to_unpublish)"
          option :source,
            type: :array,
            default: [],
            desc: "Inventory source whitelist (repeatable / CSV). e.g. AMZ_US"
          option :max_evaluated, desc: "Cap on inventory rows evaluated (smoke runs)"
          option :batch_size, default: "200", desc: "mget batch size (default: 200)"
          option :filter,
            type: :array,
            default: [],
            desc: "Rule name(s) to run (repeatable / CSV); omit to run every rule"
          option :refresh,
            type: :boolean,
            default: true,
            desc: "Refresh unpublish index at end"

          example [
            "                                          # run every rule against every source",
            "--source AMZ_US --source AMZ_CA",
            "--filter LowRatingRule --max-evaluated 1000",
          ]

          def call(inventory_index: "em_inventory", unpublish_index: "em_products_to_unpublish",
            source: [], max_evaluated: nil, batch_size: "200", filter: [], refresh: true, **)
            sources = Array(source).flat_map { |s| s.to_s.split(",") }.map(&:strip).reject(&:empty?)
            filters = Array(filter).flat_map { |s| s.to_s.split(",") }.map(&:strip).reject(&:empty?)
            resolved_filters = filters.empty? ? nil : filters.map { |n| EmTools::Core::Rules::Registry.get(n) }

            plugin = EmTools::Core::PluginRegistry.fetch(:storefront)
            runner_opts = {
              inventory_index: inventory_index,
              unpublish_index: unpublish_index,
              sources: sources,
              batch_size: Integer(batch_size),
              max_evaluated: max_evaluated ? Integer(max_evaluated) : nil,
              refresh: refresh,
            }
            runner_opts[:filters] = resolved_filters if resolved_filters
            stats = plugin.unpublish_candidates(**runner_opts).run!
            print_stats(stats)
          end
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

          private

          def print_stats(stats)
            puts "Unpublish-candidate run summary:"
            puts "  inventory_scanned:        #{stats[:inventory_scanned]}"
            puts "  evaluated:                #{stats[:evaluated]}"
            puts "  flagged (to unpublish):   #{stats[:flagged]}"
            puts "  missing_product_doc:      #{stats[:missing_product_doc]}"
            puts "  skipped_unsupported_src:  #{stats[:skipped_unsupported_source]}"
            puts "  by_source:"
            stats[:by_source].sort.each { |src, n| puts format("    %-12s %d", src, n) }
            puts "  by_reason:"
            stats[:by_reason].sort_by { |_r, n| -n }.each { |reason, n| puts format("    %-26s %d", reason, n) }
          end
        end
      end
    end
  end
end
