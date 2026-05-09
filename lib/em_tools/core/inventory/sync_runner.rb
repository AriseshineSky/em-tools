# frozen_string_literal: true

module EmTools
  module Core
    module Inventory
      # Wraps {EmTools::Core::Inventory::Sync} + {EmTools::Clients::GcsBlobFetcher} so a rake task
      # can run a single GCS-backed inventory sync (or a list of them from settings YAML) without
      # owning the file plumbing.
      class SyncRunner
        DEFAULT_GS_URI = 'gs://em-bucket/boyner-Inv.csv'

        # @param sink [#bulk] usually {EmTools::Core::Sinks::ElasticsearchBulkSink}.
        # @param fetcher_opts [Hash] forwarded to {EmTools::Clients::GcsBlobFetcher.new}.
        # @param logger [::Logger, nil]
        def initialize(sink:, fetcher_opts: {}, logger: nil)
          @sink = sink
          @fetcher_opts = fetcher_opts
          @logger = logger || EmTools::Core::Logger.for(progname: 'inventory-sync')
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
        # @return [EmTools::Core::RakeSupport::Result]
        def run_many!(sources, label: nil)
          sources.each_with_index do |src, i|
            @logger.info { "[InventorySync] [#{i + 1}/#{sources.size}] #{src.gs_uri} -> #{src.index}" }
            run_one!(
              gs_uri: src.gs_uri, index: src.index, feed_id: src.feed_id,
              refresh: src.refresh, prune_obsolete: src.prune_obsolete
            )
          end
          EmTools::Core::RakeSupport::Result.new(
            summary: "Inventory sync done (#{sources.size} source(s)#{label ? " from #{label}" : ''})"
          )
        end

        # Resolve the gs:// URI for a single-source debug run (CLI arg / env vars / default).
        # @param cli_gs_uri [String, nil]
        # @param env [Hash, ENV-like]
        # @return [String]
        def self.resolve_single_gs_uri(cli_gs_uri: nil, env: ENV)
          try_uri(cli_gs_uri) ||
            try_uri(env['INVENTORY_GS_URI']) ||
            gs_uri_from_bucket_object(env) ||
            DEFAULT_GS_URI
        end

        # @return [String]
        def self.try_uri(raw)
          s = raw.to_s.strip
          return nil if s.empty?

          assert_gs_uri!(s)
        end

        def self.gs_uri_from_bucket_object(env)
          bucket = env['INVENTORY_GCS_BUCKET'].to_s.strip
          object = env['INVENTORY_GCS_OBJECT'].to_s.strip
          return nil if bucket.empty? || object.empty?

          assert_gs_uri!("gs://#{bucket}/#{object.sub(%r{\A/+}, '')}")
        end

        def self.assert_gs_uri!(uri)
          return uri if uri.match?(%r{\Ags://[^/]+/.+\z}i)

          raise EmTools::Core::Errors::ConfigurationError,
                "expected gs://bucket/path/to/file.csv, got: #{uri.inspect}"
        end

        # Build fetcher_opts from +GCS_SERVICE_ACCOUNT_PATH+.
        def self.fetcher_opts_from_env(env: ENV)
          creds = env['GCS_SERVICE_ACCOUNT_PATH'].to_s.strip
          creds.empty? ? {} : { credentials_path: File.expand_path(creds) }
        end

        # Validate +ELASTICSEARCH_URL+ presence; raise +ConfigurationError+ if missing.
        def self.require_elasticsearch_url!(env: ENV)
          return unless env['ELASTICSEARCH_URL'].to_s.strip.empty?

          raise EmTools::Core::Errors::ConfigurationError,
                'set ELASTICSEARCH_URL (e.g. http://localhost:9200)'
        end
      end
    end
  end
end
