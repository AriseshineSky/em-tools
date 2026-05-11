# frozen_string_literal: true

require "fileutils"
require "logger"
require "securerandom"
require "tmpdir"

module EmTools
  module Plugins
    module Storefront
      module Runners
        # Downloads inventory CSV(s) from the user's Spree storefront for one or more sources
        # (e.g. +AMZ_AE+, +AMZ_CA+, +Boyner+) and syncs each into the configured Elasticsearch
        # +inventory_index+ via {EmTools::Core::Inventory::Sync}. When +prune_obsolete:+ is set
        # (the default), documents whose +inventory_feed+ matches the synced source but whose
        # +sync_batch_id+ differs from the latest run are deleted — i.e. products that no longer
        # exist on the storefront are removed from the index.
        class SyncInventory
          # @param product_util [EmTools::Plugins::Storefront::ProductUtil] preconfigured client.
          # @param sink [#bulk, #refresh, #delete_by_query] e.g. {EmTools::Core::Sinks::ElasticsearchBulkSink}.
          # @param sources [Array<String>] inventory source identifiers as expected by Spree
          #   (e.g. +"AMZ_AE"+, +"AMZ_CA"+, +"Boyner"+). Required.
          # @param index [String] target ES index (default +em_inventory+).
          # @param refresh [Boolean] whether to refresh the index after each source's sync.
          # @param prune_obsolete [Boolean] delete docs from prior batches for the same +source+.
          # @param logger [Logger, nil] # -- explicit knobs mirror the rake/CLI surface
          def initialize(product_util:, sink:, sources:,
            index: EmTools::Core::Inventory::Sync::INDEX,
            refresh: true, prune_obsolete: true, logger: nil)
            @product_util = product_util
            @sink = sink
            @sources = Array(sources).map(&:to_s).reject(&:empty?)
            raise ArgumentError, "sources is required" if @sources.empty?

            @index = index
            @refresh = refresh
            @prune_obsolete = prune_obsolete
            @logger = logger || EmTools::Core::Logger.for(progname: "storefront-sync")
          end

          # Returns +{ source => { csv_path:, byte_size:, status: :synced | :empty | :error, error: ... } }+
          # for inspection. The actual document mutations happen inside +Core::Inventory::Sync+.
          def run!
            @sources.to_h do |source|
              [source, sync_source(source)]
            end
          end

          private

          # -- I/O + log + ensure span is intentional.
          def sync_source(source)
            output_path = File.join(Dir.tmpdir, "spree-#{source}-#{SecureRandom.uuid}.csv")
            @logger.info("[SyncInventory] downloading source=#{source} -> #{output_path}")
            @product_util.spree_api.download_inventory(source, output_path)
            unless File.file?(output_path) && File.size(output_path).positive?
              @logger.warn("[SyncInventory] empty or missing CSV for source=#{source}")
              return { csv_path: output_path, byte_size: 0, status: :empty }
            end

            byte_size = File.size(output_path)
            @logger.info("[SyncInventory] syncing source=#{source} bytes=#{byte_size} index=#{@index}")
            sync = build_sync(source)
            sync.sync_from_path(output_path, refresh: @refresh)
            { csv_path: output_path, byte_size: byte_size, status: :synced }
          rescue StandardError => e
            @logger.error("[SyncInventory] failed source=#{source}: #{e.class}: #{e.message}")
            { csv_path: output_path, byte_size: 0, status: :error, error: "#{e.class}: #{e.message}" }
          ensure
            FileUtils.rm_f(output_path) if output_path && File.file?(output_path)
          end
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

          def build_sync(source)
            EmTools::Core::Inventory::Sync.new(
              sink: @sink,
              index: @index,
              feed_id: source,
              prune_obsolete: @prune_obsolete,
            )
          end
        end
      end
    end
  end
end
