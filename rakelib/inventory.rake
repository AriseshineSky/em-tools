# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength -- Rake DSL
namespace :inventory do
  desc 'Sync GCS inventory CSVs from settings YAML (or default settings). ' \
       'Args: rake \'inventory:sync[path/to/settings.yml]\'. ' \
       'Needs ELASTICSEARCH_URL; optional GCS_SERVICE_ACCOUNT_PATH.'
  task :sync, [:config_path] do |_t, args|
    EmTools::Core::RakeSupport.run do
      EmTools::Core::Inventory::SyncRunner.require_elasticsearch_url!

      raw = args[:config_path].to_s.strip
      config_path = raw.empty? ? nil : File.expand_path(raw, File.expand_path('../..', __dir__))

      sources = begin
        EmTools::Core::Inventory::SyncSources.load!(config_path)
      rescue EmTools::Core::Inventory::SyncSources::Error => e
        raise EmTools::Core::Errors::ConfigurationError, e.message
      end

      label = config_path || EmTools::Core::SettingsLoader.default_path
      EmTools::Core::Inventory::SyncRunner.new(
        sink: EmTools::Core::Sinks::ElasticsearchBulkSink.new,
        fetcher_opts: EmTools::Core::Inventory::SyncRunner.fetcher_opts_from_env
      ).run_many!(sources, label: label)
    end
  end

  desc 'Sync a single GCS CSV (debug). Target: arg gs_uri / INVENTORY_GS_URI / INVENTORY_GCS_BUCKET+OBJECT. ' \
       'Env: ELASTICSEARCH_URL (required), GCS_SERVICE_ACCOUNT_PATH, INVENTORY_INDEX, INVENTORY_REFRESH=1, ' \
       'INVENTORY_PRUNE_OBSOLETE=1, INVENTORY_FEED_ID (defaults to gs:// URI when pruning).'
  task :sync_from_gcs, [:gs_uri] do |_t, args|
    EmTools::Core::RakeSupport.run do
      EmTools::Core::Inventory::SyncRunner.require_elasticsearch_url!

      gs_uri = EmTools::Core::Inventory::SyncRunner.resolve_single_gs_uri(cli_gs_uri: args[:gs_uri])
      feed_id = ENV['INVENTORY_FEED_ID'].to_s.strip
      feed_id = gs_uri if feed_id.empty?

      EmTools::Core::Inventory::SyncRunner.new(
        sink: EmTools::Core::Sinks::ElasticsearchBulkSink.new,
        fetcher_opts: EmTools::Core::Inventory::SyncRunner.fetcher_opts_from_env
      ).run_one!(
        gs_uri: gs_uri,
        index: ENV.fetch('INVENTORY_INDEX', EmTools::Core::Inventory::Sync::INDEX),
        feed_id: feed_id,
        refresh: ENV['INVENTORY_REFRESH'] == '1',
        prune_obsolete: ENV['INVENTORY_PRUNE_OBSOLETE'] == '1'
      )

      EmTools::Core::RakeSupport::Result.new(summary: 'Inventory sync done.')
    end
  end
end
# rubocop:enable Metrics/BlockLength
