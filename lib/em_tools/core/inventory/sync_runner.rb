# frozen_string_literal: true

module EmTools
  module Core
    module Inventory
      # Wraps {EmTools::Core::Inventory::Sync} + {EmTools::Clients::GcsBlobFetcher} so a CLI
      # command can run a single GCS-backed inventory sync (or a list of them from settings YAML)
      # without owning the file plumbing.
      class SyncRunner
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
        # @param drop_fields [Array<String>] field names stripped from every doc before bulk.
        # @param feed_field [String] ES field for feed id (+inventory_feed+ or +google_ads_feed+).
        def run_one!(gs_uri:, index:, feed_id:, refresh: false, prune_obsolete: false, drop_fields: [],
          feed_field: SyncProfile::INVENTORY.feed_field)
          sync = Sync.new(
            sink: @sink,
            index: index,
            feed_id: feed_id,
            feed_field: feed_field,
            prune_obsolete: prune_obsolete,
            transforms: build_transforms(drop_fields),
            logger: @logger,
          )
          @logger.info do
            "[InventorySync] #{gs_uri} -> #{index} " \
              "(refresh=#{refresh} prune=#{prune_obsolete} feed=#{feed_id.inspect}" \
              "#{" drop=#{drop_fields.inspect}" if Array(drop_fields).any?})"
          end
          EmTools::Clients::GcsBlobFetcher.new(**@fetcher_opts).with_downloaded(gs_uri) do |path|
            sync.sync_from_path(path, refresh: refresh)
          end
        end

        # Sync a list of {SyncSources::Source}.
        # @param sources [Array]
        # @param feed_field [String]
        # @return [EmTools::Core::Cli::Runner::Result]
        def run_many!(sources, label: nil, feed_field: SyncProfile::INVENTORY.feed_field)
          sources.each_with_index do |src, i|
            @logger.info { "[InventorySync] [#{i + 1}/#{sources.size}] #{src.gs_uri} -> #{src.index}" }
            run_one!(
              gs_uri: src.gs_uri,
              index: src.index,
              feed_id: src.feed_id,
              refresh: src.refresh,
              prune_obsolete: src.prune_obsolete,
              drop_fields: Array(src.drop_fields),
              feed_field: feed_field,
            )
          end
          EmTools::Core::Cli::Runner::Result.new(
            summary: "Inventory sync done (#{sources.size} source(s)#{" from #{label}" if label})",
          )
        end

        private

        def build_transforms(drop_fields)
          fields = Array(drop_fields).compact.reject { |f| f.to_s.strip.empty? }
          return [] if fields.empty?

          [Transforms::DropFields.new(*fields)]
        end

        public

        # Resolve the gs:// URI for a single-source debug run (CLI arg / env vars / default).
        # @param cli_gs_uri [String, nil]
        # @param env [Hash, ENV-like]
        # @param profile [SyncProfile]
        # @return [String]
        def self.resolve_single_gs_uri(cli_gs_uri: nil, env: ENV, profile: SyncProfile::INVENTORY)
          try_uri(cli_gs_uri) ||
            try_uri(env[profile.env_key("GS_URI")]) ||
            gs_uri_from_bucket_object(env, profile: profile) ||
            profile.default_gs_uri
        end

        # @return [String]
        def self.try_uri(raw)
          s = raw.to_s.strip
          return if s.empty?

          assert_gs_uri!(s)
        end

        def self.gs_uri_from_bucket_object(env, profile: SyncProfile::INVENTORY)
          bucket = env[profile.env_key("GCS_BUCKET")].to_s.strip
          object = env[profile.env_key("GCS_OBJECT")].to_s.strip
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
        # @param profile [SyncProfile]
        # @return [EmTools::Core::Cli::Runner::Result]
        def self.run_from_settings!(config_path: nil, env: ENV, prefer_data_cluster: false, sink: nil, logger: nil,
          profile: SyncProfile::INVENTORY)
          require_cluster_configured!(env: env, prefer_data_cluster: prefer_data_cluster)
          path = string_present(config_path) ? File.expand_path(config_path) : nil
          sources = load_sources_or_fail!(path, profile: profile)
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
              runner.run_many!(group, label: nil, feed_field: profile.feed_field)
            end

          EmTools::Core::Cli::Runner::Result.new(
            summary: "#{profile.config_label} sync done (#{sources.size} source(s) from #{label}; " \
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
        # @param profile [SyncProfile]
        # @return [EmTools::Core::Cli::Runner::Result]
        def self.run_one_from_env!(cli_gs_uri: nil, env: ENV, prefer_data_cluster: false, sink: nil, logger: nil,
          profile: SyncProfile::INVENTORY)
          require_cluster_configured!(env: env, prefer_data_cluster: prefer_data_cluster)

          gs_uri = resolve_single_gs_uri(cli_gs_uri: cli_gs_uri, env: env, profile: profile)
          feed_id = string_present(env[profile.env_key("FEED_ID")]) || gs_uri

          new(
            sink: sink || default_sink(prefer_data_cluster: prefer_data_cluster),
            fetcher_opts: fetcher_opts_from_env(env: env),
            logger: logger,
          ).run_one!(
            gs_uri: gs_uri,
            index: env.fetch(profile.env_key("INDEX"), profile.default_index),
            feed_id: feed_id,
            refresh: env[profile.env_key("REFRESH")] == "1",
            prune_obsolete: env[profile.env_key("PRUNE_OBSOLETE")] == "1",
            drop_fields: drop_fields_from_env(env, profile: profile),
            feed_field: profile.feed_field,
          )

          EmTools::Core::Cli::Runner::Result.new(summary: "#{profile.config_label} sync done (#{gs_uri}).")
        end

        # Parse +*_DROP_FIELDS+ as comma-separated field names.
        def self.drop_fields_from_env(env, profile: SyncProfile::INVENTORY)
          raw = env[profile.env_key("DROP_FIELDS")].to_s.strip
          return [] if raw.empty?

          raw.split(",").map(&:strip).reject(&:empty?)
        end
        private_class_method :drop_fields_from_env

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

        def self.load_sources_or_fail!(path, profile: SyncProfile::INVENTORY)
          SyncSources.load!(path, profile: profile)
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
