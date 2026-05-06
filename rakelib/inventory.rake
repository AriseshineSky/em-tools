# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength -- Rake DSL
module InventoryRakeHelpers
  module_function

  DEFAULT_GS_URI = 'gs://em-bucket/boyner-Inv.csv'

  def run_gcs_inventory_sync(**opts)
    sync = Em::Tools::InventorySync.new(
      sink: opts.fetch(:sink),
      index: opts.fetch(:index),
      feed_id: opts.fetch(:feed_id),
      prune_obsolete: opts.fetch(:prune_obsolete, false)
    )
    Em::Tools::GcsBlobFetcher.new(**opts.fetch(:fetcher_opts)).with_downloaded(opts.fetch(:gs_uri)) do |path|
      sync.sync_from_path(path, refresh: opts.fetch(:refresh))
    end
  end

  # Precedence: +cli_gs_uri+ > +INVENTORY_GS_URI+ > +INVENTORY_GCS_BUCKET+ + +INVENTORY_GCS_OBJECT+ > default.
  def inventory_gs_uri(cli_gs_uri = nil)
    try_uri(cli_gs_uri) ||
      try_uri(ENV['INVENTORY_GS_URI']) ||
      gs_uri_from_bucket_object ||
      DEFAULT_GS_URI
  end

  def try_uri(raw)
    s = raw.to_s.strip
    return nil if s.empty?

    assert_gs_uri!(s)
  end

  def gs_uri_from_bucket_object
    bucket = ENV['INVENTORY_GCS_BUCKET'].to_s.strip
    object = ENV['INVENTORY_GCS_OBJECT'].to_s.strip
    return nil if bucket.empty? || object.empty?

    object = object.sub(%r{\A/+}, '')
    assert_gs_uri!("gs://#{bucket}/#{object}")
  end

  def assert_gs_uri!(uri)
    return uri if uri.match?(%r{\Ags://[^/]+/.+\z}i)

    raise ArgumentError, "expected gs://bucket/path/to/file.csv, got: #{uri.inspect}"
  end

  def resolve_inventory_yaml_path(root, relative)
    rel = relative.to_s.strip
    return nil if rel.empty?

    File.expand_path(rel, root)
  end
end

namespace :inventory do
  desc 'Sync GCS inventory CSVs from merged settings (inventory_sync.sources) or a YAML path arg. ' \
       'Needs ELASTICSEARCH_URL; optional GCS_SERVICE_ACCOUNT_PATH.'
  task :sync, [:config_path] do |_t, args|
    require 'em/tools'

    if ENV['ELASTICSEARCH_URL'].to_s.strip.empty?
      warn 'error: set ELASTICSEARCH_URL (e.g. http://localhost:9200)'
      exit 1
    end

    root = File.expand_path('..', __dir__)
    config_path = InventoryRakeHelpers.resolve_inventory_yaml_path(root, args[:config_path])

    creds = ENV['GCS_SERVICE_ACCOUNT_PATH'].to_s.strip
    fetcher_opts = creds.empty? ? {} : { credentials_path: File.expand_path(creds) }
    sink = Em::Tools::ElasticsearchBulkSink.new

    begin
      sources = Em::Tools::InventorySyncSources.load!(config_path)
    rescue Em::Tools::InventorySyncSources::Error => e
      warn "error: #{e.message}"
      exit 1
    end

    config_label = config_path || Em::Tools::SettingsLoader.default_path
    puts "Inventory sync from #{config_label} (#{sources.size} source(s))"
    sources.each_with_index do |src, i|
      puts "[#{i + 1}/#{sources.size}] #{src.gs_uri} -> index=#{src.index} refresh=#{src.refresh} " \
           "feed_id=#{src.feed_id.inspect} prune=#{src.prune_obsolete}"
      InventoryRakeHelpers.run_gcs_inventory_sync(
        gs_uri: src.gs_uri,
        index: src.index,
        refresh: src.refresh,
        feed_id: src.feed_id,
        prune_obsolete: src.prune_obsolete,
        fetcher_opts: fetcher_opts,
        sink:
      )
    end
    puts 'Done.'
  end

  desc 'Sync a single GCS CSV (debug). Target: arg gs_uri, or INVENTORY_GS_URI, or INVENTORY_GCS_BUCKET+OBJECT; ' \
       'ELASTICSEARCH_URL; optional GCS_SERVICE_ACCOUNT_PATH, INVENTORY_INDEX, INVENTORY_REFRESH=1, ' \
       'INVENTORY_PRUNE_OBSOLETE=1, INVENTORY_FEED_ID (defaults to resolved gs:// URI when pruning)'
  task :sync_from_gcs, [:gs_uri] do |_t, args|
    require 'em/tools'

    if ENV['ELASTICSEARCH_URL'].to_s.strip.empty?
      warn 'error: set ELASTICSEARCH_URL (e.g. http://localhost:9200)'
      exit 1
    end

    begin
      gs_uri = InventoryRakeHelpers.inventory_gs_uri(args[:gs_uri])
    rescue ArgumentError => e
      warn "error: #{e.message}"
      exit 1
    end

    index = ENV.fetch('INVENTORY_INDEX', Em::Tools::InventorySync::INDEX)
    refresh = ENV['INVENTORY_REFRESH'] == '1'
    prune = ENV['INVENTORY_PRUNE_OBSOLETE'] == '1'
    feed_id = ENV['INVENTORY_FEED_ID'].to_s.strip
    feed_id = gs_uri if feed_id.empty?
    creds = ENV['GCS_SERVICE_ACCOUNT_PATH'].to_s.strip
    fetcher_opts = creds.empty? ? {} : { credentials_path: File.expand_path(creds) }
    sink = Em::Tools::ElasticsearchBulkSink.new
    puts "Inventory sync: #{gs_uri} -> #{index} (refresh=#{refresh} prune=#{prune} feed_id=#{feed_id.inspect})"
    InventoryRakeHelpers.run_gcs_inventory_sync(
      gs_uri: gs_uri,
      index: index,
      refresh: refresh,
      feed_id: feed_id,
      prune_obsolete: prune,
      fetcher_opts: fetcher_opts,
      sink:
    )
    puts 'Done.'
  end
end
# rubocop:enable Metrics/BlockLength
