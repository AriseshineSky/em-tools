# frozen_string_literal: true

require "json"
require "optparse"

module EmTools
  module Plugins
    module Storefront
      module Cli
        # CLI for {EmTools::Plugins::Storefront::Runners::UnpublishCandidates}.
        # Iterates +em_inventory+, runs the rule registry against the matching Amazon-side
        # product doc, and indexes failing ASINs into +em_products_to_unpublish+.
        class UnpublishCandidates
          def run(argv)
            options = parse_options(argv)
            return 0 if options.nil?

            stats = run_pipeline(options)
            print_stats(stats)
            0
          end

          private

          def parse_options(argv)
            options = {
              inventory_index: "em_inventory",
              unpublish_index: "em_products_to_unpublish",
              sources: [],
              max_evaluated: nil,
              batch_size: 200,
              refresh: true,
              filters: nil,
            }
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools storefront:unpublish-candidates [options]

                For each Amazon-sourced row in --inventory-index, look up the enriched product
                doc in amz_products_api_<mp>_v2, run all rules from EmTools::Core::Rules::Registry
                against it, and bulk-index the IDs of products that fail any rule into
                --unpublish-index.
              BANNER
              opts.on("--inventory-index NAME", "Source ES index (default em_inventory)") do |v|
                options[:inventory_index] = v
              end
              opts.on("--unpublish-index NAME", "Target ES index (default em_products_to_unpublish)") do |v|
                options[:unpublish_index] = v
              end
              opts.on("--source SOURCE", "Inventory source whitelist (repeatable). e.g. AMZ_US") do |v|
                options[:sources] << v
              end
              opts.on("--max-evaluated N", Integer, "Cap on inventory rows evaluated (smoke runs)") do |v|
                options[:max_evaluated] = v
              end
              opts.on("--batch-size N", Integer, "mget batch size (default 200)") { |v| options[:batch_size] = v }
              opts.on("--filter NAME", "Run only this rule (repeatable)") do |v|
                options[:filters] ||= []
                options[:filters] << EmTools::Core::Rules::Registry.get(v)
              end
              opts.on("--[no-]refresh", "Refresh unpublish index at end (default: yes)") { |v| options[:refresh] = v }
              opts.on_tail("-h", "--help") do
                puts opts
                return nil
              end
            end
            parser.parse!(argv)
            options[:sources] = options[:sources].flat_map { |s| s.split(",") }.map(&:strip).reject(&:empty?)
            options
          end
          # rubocop:enable Metrics/BlockLength

          def run_pipeline(options)
            plugin = EmTools::Core::PluginRegistry.fetch(:storefront)
            runner_opts = {
              inventory_index: options[:inventory_index],
              unpublish_index: options[:unpublish_index],
              sources: options[:sources],
              batch_size: options[:batch_size],
              max_evaluated: options[:max_evaluated],
              refresh: options[:refresh],
            }
            runner_opts[:filters] = options[:filters] if options[:filters]
            plugin.unpublish_candidates(**runner_opts).run!
          end

          # -- terminal column padding only
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
          # rubocop:enable Style/FormatStringToken
        end
      end
    end
  end
end
