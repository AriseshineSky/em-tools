# frozen_string_literal: true

module EmTools
  module Core
    module Inventory
      # Wraps {EmTools::Core::Inventory::Sync} + {EmTools::Clients::GcsBlobFetcher} so a CLI
      # command can run a single GCS-backed inventory sync (or a list of them from settings YAML)
      # without owning the file plumbing.
      class SyncRunner
        DEFAULT_GS_URI = "gs://em-bucket/boyner-Inv.csv"

        # @param sink [#bulk] usually {EmTools::Core::Sinks::ElasticsearchBulkSink}.
        # @param fetcher_opts [Hash] forwarded to {EmTools::Clients::GcsBlobFetcher.new}.
        # @param logger [::Logger, nil]
        def initialize(sink:, fetcher_opts: {}, logger: nil)
          @sink = sink
          @fetcher_opts = fetcher_opts
          @logger = logger || EmTools::Core::Logger.for(progname: "inventory-sync")
        end

        # Sync a single GCS CSV → ES.
        # @param gs_uri [String]
        # @param index [String]
        # @param feed_id [String, nil]
        # @param refresh [Boolean]
        # @param prune_obsolete [Boolean]
        def run_one!(gs_uri:, index:, feed_id:, refresh: false, prune_obsolete: false)
          sync = Sync.new(sink: @sink, index: index, feed_id: feed_id, prune_obsolete: prune_obsolete, logger: @logger)
          @logger.info do
            "[InventorySync] #{gs_uri} -> #{index} " \
              "(refresh=#{refresh} prune=#{prune_obsolete} feed=#{feed_id.inspect})"
          end
          EmTools::Clients::GcsBlobFetcher.new(**@fetcher_opts).with_downloaded(gs_uri) do |path|
            sync.sync_from_path(path, refresh: refresh)
          end
        end

        # Sync a list of {SyncSources::Source}.
        # @param sources [Array]
        # @return [EmTools::Core::Cli::Runner::Result]
        def run_many!(sources, label: nil)
          sources.each_with_index do |src, i|
            @logger.info { "[InventorySync] [#{i + 1}/#{sources.size}] #{src.gs_uri} -> #{src.index}" }
            run_one!(
              gs_uri: src.gs_uri,
              index: src.index,
              feed_id: src.feed_id,
              refresh: src.refresh,
              prune_obsolete: src.prune_obsolete,
            )
          end
          EmTools::Core::Cli::Runner::Result.new(
            summary: "Inventory sync done (#{sources.size} source(s)#{" from #{label}" if label})",
          )
        end

        # Resolve the gs:// URI for a single-source debug run (CLI arg / env vars / default).
        # @param cli_gs_uri [String, nil]
        # @param env [Hash, ENV-like]
        # @return [String]
        def self.resolve_single_gs_uri(cli_gs_uri: nil, env: ENV)
          try_uri(cli_gs_uri) ||
            try_uri(env["INVENTORY_GS_URI"]) ||
            gs_uri_from_bucket_object(env) ||
            DEFAULT_GS_URI
        end

        # @return [String]
        def self.try_uri(raw)
          s = raw.to_s.strip
          return if s.empty?

          assert_gs_uri!(s)
        end

        def self.gs_uri_from_bucket_object(env)
          bucket = env["INVENTORY_GCS_BUCKET"].to_s.strip
          object = env["INVENTORY_GCS_OBJECT"].to_s.strip
          return if bucket.empty? || object.empty?

          assert_gs_uri!("gs://#{bucket}/#{object.sub(%r{\A/+}, "")}")
        end

        def self.assert_gs_uri!(uri)
          return uri if uri.match?(%r{\Ags://[^/]+/.+\z}i)

          raise EmTools::Core::Errors::ConfigurationError,
            "expected gs://bucket/path/to/file.csv, got: #{uri.inspect}"
        end

        # Build fetcher_opts from +GCS_SERVICE_ACCOUNT_PATH+.
        def self.fetcher_opts_from_env(env: ENV)
          creds = env["GCS_SERVICE_ACCOUNT_PATH"].to_s.strip
          creds.empty? ? {} : { credentials_path: File.expand_path(creds) }
        end

        # Validate +ELASTICSEARCH_URL+ presence; raise +ConfigurationError+ if missing.
        def self.require_elasticsearch_url!(env: ENV)
          return unless env["ELASTICSEARCH_URL"].to_s.strip.empty?

          raise EmTools::Core::Errors::ConfigurationError,
            "set ELASTICSEARCH_URL (e.g. http://localhost:9200)"
        end

        # Settings-driven entrypoint used by +inventory-sync+ and any future
        # scheduler / cron job that wants to run all configured sources end to
        # end. Validates env, loads sources, translates the +SyncSources+ error
        # class to a {EmTools::Core::Errors::ConfigurationError}, then runs each
        # source against its declared cluster.
        #
        # Cluster precedence (per source):
        # 1. per-source +cluster:+ in YAML (always wins),
        # 2. section default (+inventory_sync.cluster+),
        # 3. +prefer_data_cluster+ flag (CLI +--data+) — equivalent to a
        #    runtime default of +"data"+,
        # 4. primary cluster (+ELASTICSEARCH_URL+).
        #
        # @param config_path [String, nil] explicit YAML path; +nil+ falls back to the
        #   merged settings YAML (+inventory_sync+ section).
        # @param env [Hash, ENV-like]
        # @param prefer_data_cluster [Boolean] default cluster for sources without an
        #   explicit +cluster:+; ignored once a source declares one.
        # @param sink [#bulk, nil] when given, **all** sources are forced through this sink
        #   (test/override path); per-source +cluster:+ is ignored.
        # @param logger [::Logger, nil]
        # @return [EmTools::Core::Cli::Runner::Result]
        def self.run_from_settings!(config_path: nil, env: ENV, prefer_data_cluster: false, sink: nil, logger: nil)
          require_cluster_configured!(env: env, prefer_data_cluster: prefer_data_cluster)
          path = string_present(config_path) ? File.expand_path(config_path) : nil
          sources = load_sources_or_fail!(path)
          fallback_cluster = prefer_data_cluster ? "data" : nil
          label = path || EmTools::Core::SettingsLoader.default_path

          summary = sources
            .group_by { |s| effective_cluster(s, fallback_cluster) }
            .each do |cluster, group|
              runner = new(
                sink: sink || default_sink_for_cluster(cluster),
                fetcher_opts: fetcher_opts_from_env(env: env),
                logger: logger,
              )
              runner.run_many!(group, label: nil)
            end

          EmTools::Core::Cli::Runner::Result.new(
            summary: "Inventory sync done (#{sources.size} source(s) from #{label}; " \
              "#{format_cluster_breakdown(summary)})",
          )
        end

        # Single-CSV entrypoint used by +inventory-sync-from-gcs+. Resolves the gs:// URI
        # (CLI arg / env / default), reads target index + flags from env, and bulk-indexes
        # one CSV. Symmetric with {.run_from_settings!} so the two CLI commands stay thin.
        #
        # @param cli_gs_uri [String, nil]
        # @param env [Hash, ENV-like]
        # @param prefer_data_cluster [Boolean] same semantics as {.run_from_settings!}.
        # @param sink [#bulk, nil]
        # @param logger [::Logger, nil]
        # @return [EmTools::Core::Cli::Runner::Result]
        def self.run_one_from_env!(cli_gs_uri: nil, env: ENV, prefer_data_cluster: false, sink: nil, logger: nil)
          require_cluster_configured!(env: env, prefer_data_cluster: prefer_data_cluster)

          gs_uri = resolve_single_gs_uri(cli_gs_uri: cli_gs_uri, env: env)
          feed_id = string_present(env["INVENTORY_FEED_ID"]) || gs_uri

          new(
            sink: sink || default_sink(prefer_data_cluster: prefer_data_cluster),
            fetcher_opts: fetcher_opts_from_env(env: env),
            logger: logger,
          ).run_one!(
            gs_uri: gs_uri,
            index: env.fetch("INVENTORY_INDEX", EmTools::Core::Inventory::Sync::INDEX),
            feed_id: feed_id,
            refresh: env["INVENTORY_REFRESH"] == "1",
            prune_obsolete: env["INVENTORY_PRUNE_OBSOLETE"] == "1",
          )

          EmTools::Core::Cli::Runner::Result.new(summary: "Inventory sync done (#{gs_uri}).")
        end

        # Validates that *some* cluster URL is reachable. When +prefer_data_cluster+ is true,
        # accept either +DATA_ELASTICSEARCH_URL+ or +ELASTICSEARCH_URL+; otherwise require
        # +ELASTICSEARCH_URL+ (the long-standing primary-cluster contract).
        def self.require_cluster_configured!(env: ENV, prefer_data_cluster: false)
          return require_elasticsearch_url!(env: env) unless prefer_data_cluster
          return if string_present(env["DATA_ELASTICSEARCH_URL"]) || string_present(env["ELASTICSEARCH_URL"])

          raise EmTools::Core::Errors::ConfigurationError,
            "set DATA_ELASTICSEARCH_URL (or ELASTICSEARCH_URL as fallback)"
        end

        def self.string_present(value)
          s = value.to_s.strip
          s.empty? ? nil : s
        end
        private_class_method :string_present

        def self.load_sources_or_fail!(path)
          SyncSources.load!(path)
        rescue SyncSources::Error => e
          raise EmTools::Core::Errors::ConfigurationError, e.message
        end
        private_class_method :load_sources_or_fail!

        def self.default_sink(prefer_data_cluster:)
          client = EmTools::Core::Config.elasticsearch_client(prefer_data_cluster: prefer_data_cluster)
          EmTools::Core::Sinks::ElasticsearchBulkSink.new(client)
        end
        private_class_method :default_sink

        def self.default_sink_for_cluster(cluster)
          client = EmTools::Core::Config.elasticsearch_client(cluster: cluster)
          EmTools::Core::Sinks::ElasticsearchBulkSink.new(client)
        end
        private_class_method :default_sink_for_cluster

        def self.effective_cluster(source, fallback)
          string_present(source.cluster) || fallback || "primary"
        end
        private_class_method :effective_cluster

        def self.format_cluster_breakdown(grouped)
          grouped
            .map { |cluster, group| "#{cluster}=#{group.size}" }
            .sort
            .join(", ")
        end
        private_class_method :format_cluster_breakdown
      end
    end
  end
end
