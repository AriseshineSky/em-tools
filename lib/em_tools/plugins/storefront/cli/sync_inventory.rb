# frozen_string_literal: true

require "optparse"

module EmTools
  module Plugins
    module Storefront
      module Cli
        # CLI for {EmTools::Plugins::Storefront::Runners::SyncInventory}.
        # Reads Spree credentials from +EM_TOOLS_SITE_STOREFRONT_{ENDPOINT,TOKEN}+ (or
        # +--endpoint+/+--token+ flags), then for every requested +--source+ downloads the
        # storefront inventory CSV and syncs it into +em_inventory+ (with prune-on-missing).
        class SyncInventory
          def run(argv)
            options = parse_options(argv)
            return 0 if options.nil?

            credentials = resolve_credentials!(options)
            run_sync(credentials, options)
            0
          end

          private

          def parse_options(argv)
            options = { sources: [], refresh: true, prune: true, index: nil }
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools storefront-sync-inventory [options]

                Download inventory CSV from the user's Spree storefront for one or more sources
                and bulk-index into Elasticsearch (default index: em_inventory). Documents
                belonging to the synced source whose sync_batch_id is older than the latest
                run are deleted (i.e. products that no longer exist on the storefront are
                pruned from the index).

                Credentials default to env: EM_TOOLS_SITE_STOREFRONT_ENDPOINT, EM_TOOLS_SITE_STOREFRONT_TOKEN.
              BANNER
              opts.on("--endpoint URL", "Spree API endpoint (default $EM_TOOLS_SITE_STOREFRONT_ENDPOINT)") do |v|
                options[:endpoint] = v
              end
              opts.on("--token TOKEN", "Spree API token (default $EM_TOOLS_SITE_STOREFRONT_TOKEN)") do |v|
                options[:token] = v
              end
              opts.on("--source SOURCE", "Inventory source to sync (repeatable). e.g. AMZ_AE, AMZ_CA, Boyner") do |v|
                options[:sources] << v
              end
              opts.on("--index NAME", "Override target inventory index (default em_inventory)") do |v|
                options[:index] = v
              end
              opts.on("--[no-]refresh", "Refresh index after sync (default: yes)") { |v| options[:refresh] = v }
              opts.on("--[no-]prune", "Delete docs that no longer exist on the source (default: yes)") do |v|
                options[:prune] = v
              end
              opts.on_tail("-h", "--help") do
                puts opts
                return nil
              end
            end
            parser.parse!(argv)
            options[:sources] = options[:sources].flat_map { |s| s.split(",") }.map(&:strip).reject(&:empty?)
            if options[:sources].empty?
              warn(parser.help)
              warn("error: at least one --source is required (e.g. --source AMZ_AE)")
              return
            end
            options
          end
          # rubocop:enable Metrics/BlockLength

          def resolve_credentials!(options)
            site = EmTools::Core::Config.site("storefront")
            endpoint = options[:endpoint] || site["endpoint"]
            token = options[:token] || site["token"]
            if endpoint.to_s.strip.empty? || token.to_s.strip.empty?
              warn("error: missing Spree credentials. Set EM_TOOLS_SITE_STOREFRONT_ENDPOINT + " \
                "_TOKEN, or pass --endpoint / --token.")
              exit(2)
            end
            { endpoint: endpoint, token: token }
          end

          def run_sync(credentials, options)
            product_util = EmTools::Plugins::Storefront::ProductUtil.new(credentials[:endpoint], credentials[:token])
            sink = EmTools::Core::Sinks::ElasticsearchBulkSink.new
            runner_opts = {
              product_util: product_util,
              sink: sink,
              sources: options[:sources],
              refresh: options[:refresh],
              prune_obsolete: options[:prune],
            }
            runner_opts[:index] = options[:index] if options[:index]
            results = EmTools::Plugins::Storefront::Runners::SyncInventory.new(**runner_opts).run!
            print_summary(results)
          end

          # -- terminal column padding only
          def print_summary(results)
            puts "Inventory sync results:"
            results.each do |source, info|
              puts format("  %-12s %s bytes=%d %s", source, info[:status], info[:byte_size], info[:error] || "")
            end
          end
          # rubocop:enable Style/FormatStringToken
        end
      end
    end
  end
end
