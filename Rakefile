# frozen_string_literal: true

# Load .env when dotenv is installed (optional dev dependency).
# rubocop:disable Lint/SuppressedException
begin
  require 'dotenv/load'
rescue LoadError
end
# rubocop:enable Lint/SuppressedException

require 'bundler/gem_tasks'

namespace :gcs do
  desc 'Download AMZ marketplace seeds from GCS to tmp/gcs/amz_<mp>.txt'
  task :download_seeds do
    require 'em/tools'

    creds_raw = ENV['GCS_SERVICE_ACCOUNT_PATH'].to_s.strip
    if creds_raw.empty?
      warn 'error: set GCS_SERVICE_ACCOUNT_PATH to your service account JSON file'
      exit 1
    end
    creds_path = File.expand_path(creds_raw)
    unless File.file?(creds_path)
      warn "error: GCS_SERVICE_ACCOUNT_PATH is not a file: #{creds_path}"
      exit 1
    end

    bucket = ENV.fetch('GCS_BUCKET', 'em-bucket')
    prefix = ENV.fetch('GCS_SEEDS_PREFIX', 'em-analytics')
    root = File.expand_path(__dir__)
    target = File.join(root, 'tmp')

    Em::Tools::LowestOfferSeedFiles.sync_from_gcs(
      target,
      marketplaces: Em::Tools::LowestOfferListingsCoverageQuery::DEFAULT_MARKETPLACES,
      creds_path: creds_path,
      bucket: bucket,
      prefix: prefix,
      force: true
    )
    puts "Seeds synced to #{target} (GCS objects AMZ_<MP>.txt -> amz_<mp>.txt)"
  end
end

namespace :lowest_offer do
  desc 'Publish lowest-offer snapshot to ES. Seeds: set LOWEST_OFFER_SEED_DIR to a directory containing ' \
       'amz_<mp>.txt (or ebay_<mp>.txt), e.g. LOWEST_OFFER_SEED_DIR=tmp with ./tmp/amz_ca.txt for CA. ' \
       'ES: LOWEST_OFFER_ASIN_FIELD (default asin.keyword), raw ASIN terms. ' \
       'LOWEST_OFFER_TERMS_BATCH_SIZE (default 2000) for large seeds. ' \
       'Missing ASINs -> LOWEST_OFFER_MISSING_ASINS_DIR (default tmp/lowest_offer_missing_asins), ' \
       'LOWEST_OFFER_WRITE_MISSING_ASINS=false to disable. ' \
       'GCS in-memory if seed dir unset. ' \
       'If seed dir is set and a file is missing, downloads GCS AMZ_<MP>.txt (needs GCS_SERVICE_ACCOUNT_PATH). ' \
       'LOWEST_OFFER_SEEDS_FORCE_DOWNLOAD=1 re-downloads all needed seeds and overwrites amz_<mp>.txt. ' \
       'Optional marketplaces (zsh: quote brackets): rake \'lowest_offer:publish_snapshot[us]\'. ' \
       'Otherwise LOWEST_OFFER_MARKETPLACES or defaults. One UTC +snapshot_time+ applies to all marketplaces ' \
       'in this run (activity time windows + captured_at). Debug: LOWEST_OFFER_RAKE_DEBUG=1 (opens IRB).'
  task :publish_snapshot, [:marketplaces] do |_t, args|
    require 'em/tools'
    require 'time'

    client = Em::Tools::ElasticsearchClient.new
    query_opts = { es_client: client }

    seed_dir = ENV['LOWEST_OFFER_SEED_DIR'].to_s.strip
    if seed_dir.empty?
      creds_raw = ENV['GCS_SERVICE_ACCOUNT_PATH'].to_s.strip
      if creds_raw.empty?
        warn 'error: set LOWEST_OFFER_SEED_DIR to a directory with amz_<mp>.txt seeds, or set ' \
             'GCS_SERVICE_ACCOUNT_PATH to load the same AMZ_*.txt objects from GCS in memory'
        exit 1
      end
      creds_path = File.expand_path(creds_raw)
      unless File.file?(creds_path)
        warn "error: GCS_SERVICE_ACCOUNT_PATH is not a file: #{creds_path}"
        exit 1
      end

      bucket = ENV.fetch('GCS_BUCKET', 'em-bucket')
      prefix = ENV.fetch('GCS_SEEDS_PREFIX', 'em-analytics').sub(%r{/+\z}, '')

      gcs = Em::Tools::GcsHelper.new(creds_path, bucket, prefix)
      query_opts[:seed_text_fetcher] = lambda do |mp|
        blob_name = "#{prefix}/sources/AMZ_#{mp.upcase}.txt"
        gcs.download_string(blob_name)
      end
    else
      seed_dir_expanded = File.expand_path(seed_dir)
      marketplaces = Em::Tools::LowestOfferListingsCoverageQuery.marketplaces_for_publish(args[:marketplaces])
      force = ENV['LOWEST_OFFER_SEEDS_FORCE_DOWNLOAD'] == '1'
      needs_sync = force || marketplaces.any? do |mp|
        !Em::Tools::LowestOfferSeedFiles.seed_file_present?(seed_dir_expanded, mp)
      end

      if needs_sync
        creds_raw = ENV['GCS_SERVICE_ACCOUNT_PATH'].to_s.strip
        if creds_raw.empty?
          warn 'error: missing seed files under LOWEST_OFFER_SEED_DIR; set GCS_SERVICE_ACCOUNT_PATH to pull ' \
               'AMZ_<MP>.txt from GCS (or unset LOWEST_OFFER_SEED_DIR to use in-memory GCS only). ' \
               'Use LOWEST_OFFER_SEEDS_FORCE_DOWNLOAD=1 to overwrite existing amz_<mp>.txt.'
          exit 1
        end
        creds_path = File.expand_path(creds_raw)
        unless File.file?(creds_path)
          warn "error: GCS_SERVICE_ACCOUNT_PATH is not a file: #{creds_path}"
          exit 1
        end

        bucket = ENV.fetch('GCS_BUCKET', 'em-bucket')
        prefix = ENV.fetch('GCS_SEEDS_PREFIX', 'em-analytics')
        puts "Syncing seeds from GCS -> #{seed_dir_expanded} (marketplaces=#{marketplaces.join(',')}, force=#{force})"
        Em::Tools::LowestOfferSeedFiles.sync_from_gcs(
          seed_dir_expanded,
          marketplaces: marketplaces,
          creds_path: creds_path,
          bucket: bucket,
          prefix: prefix,
          force: force
        )
      end

      query_opts[:seed_dir] = seed_dir_expanded
    end
    cli_mps = args[:marketplaces].to_s.split(',').map(&:strip).reject(&:empty?).map(&:downcase)
    query_opts[:marketplaces] = cli_mps if cli_mps.any?

    snapshot_time = Time.now.utc
    rows = Em::Tools::LowestOfferListingsCoverageQuery.new(**query_opts.merge(snapshot_time: snapshot_time)).fetch_all

    if query_opts[:seed_dir]
      rows.each do |row|
        err = row[:error] || row['error']
        next if err && !err.to_s.strip.empty?

        loaded = row[:seed_asins_loaded] || row['seed_asins_loaded']
        present = row[:seed_file_present] || row['seed_file_present']
        next if loaded.to_i.positive?

        warn "error: no seed ASINs loaded for #{row[:marketplace] || row['marketplace']} " \
             "(seed_file_present=#{present.inspect}, seed_asins_loaded=#{loaded.inspect}). " \
             "Check LOWEST_OFFER_SEED_DIR (#{query_opts[:seed_dir]}) contains amz_#{(row[:marketplace] || row['marketplace']).to_s.downcase}.txt " \
             'or ebay_<mp>.txt (tab + JSON column 2 with source_product_id).'
        exit 1
      end
    end

    Em::Tools::LowestOfferCoverageSnapshot.persist!(
      rows,
      captured_at: snapshot_time,
      es_client: client,
      refresh: true
    )
    mps_label = if query_opts[:marketplaces]
                  query_opts[:marketplaces].join(',')
                elsif ENV['LOWEST_OFFER_MARKETPLACES'].to_s.strip.empty?
                  'default list'
                else
                  ENV['LOWEST_OFFER_MARKETPLACES'].strip
                end
    puts "Indexed #{rows.size} marketplace row(s) (#{mps_label}) -> #{Em::Tools::LowestOfferCoverageSnapshot.index_name}"
  end

  desc 'Download GCS seeds (gcs:download_seeds) then publish_snapshot'
  task download_and_publish: %w[gcs:download_seeds lowest_offer:publish_snapshot]
end

task default: %i[]
