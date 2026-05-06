# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength -- Rake DSL
namespace :ebay_listings do
  desc 'Publish eBay listings coverage snapshot to ES (single configurable products index). ' \
       'Target index: EBAY_LISTINGS_COVERAGE_INDEX (default ebay_us_products). ' \
       'Terms field: EBAY_LISTINGS_COVERAGE_ID_FIELD (default product_id.keyword); time buckets: ' \
       'EBAY_LISTINGS_COVERAGE_TIME_FIELD (default time). ' \
       'Seeds: EBAY_LISTINGS_COVERAGE_SEED_DIR with ebay_<mp>.txt (tab + JSON column 2, source_product_id), ' \
       'or EBAY_LISTINGS_COVERAGE_SEED_FILE. Or EBAY_LISTINGS_COVERAGE_ID_SOURCE=inventory loads ids from ES ' \
       '(EBAY_LISTINGS_COVERAGE_INVENTORY_*). ' \
       'Optional GCS: unset seed dir, set GCS_SERVICE_ACCOUNT_PATH; loads prefix/sources/EBAY_<MP>.txt in memory. ' \
       'Missing seed ids -> EBAY_LISTINGS_COVERAGE_MISSING_IDS_DIR (default tmp/ebay_listings_missing_ids); ' \
       'EBAY_LISTINGS_COVERAGE_WRITE_MISSING_IDS=false to disable. ' \
       'Marketplace (seed suffix): rake \'ebay_listings:publish_snapshot[us]\' ' \
       'or EBAY_LISTINGS_COVERAGE_MARKETPLACE.'
  task :publish_snapshot, [:marketplace] do |_t, args|
    require 'em/tools'
    require 'time'

    client = Em::Clients::ElasticsearchClient.new
    mp = args[:marketplace].to_s.strip.downcase
    mp = ENV['EBAY_LISTINGS_COVERAGE_MARKETPLACE'].to_s.strip.downcase if mp.empty?
    mp = 'us' if mp.empty?

    query_opts = { es_client: client, marketplace: mp }
    seed_dir = ENV['EBAY_LISTINGS_COVERAGE_SEED_DIR'].to_s.strip
    seed_file = ENV['EBAY_LISTINGS_COVERAGE_SEED_FILE'].to_s.strip
    inventory_mode = ENV['EBAY_LISTINGS_COVERAGE_ID_SOURCE'].to_s.strip.downcase == 'inventory'

    unless inventory_mode
      if !seed_file.empty?
        seed_path = File.expand_path(seed_file)
        unless File.file?(seed_path)
          warn "error: EBAY_LISTINGS_COVERAGE_SEED_FILE is not a file: #{seed_path}"
          exit 1
        end
      elsif !seed_dir.empty?
        seed_dir_expanded = File.expand_path(seed_dir)
        path = File.join(seed_dir_expanded, "ebay_#{mp}.txt")
        unless File.file?(path)
          warn "error: expected seed file #{path} under EBAY_LISTINGS_COVERAGE_SEED_DIR"
          exit 1
        end

        query_opts[:seed_dir] = seed_dir_expanded
      else
        creds_raw = ENV['GCS_SERVICE_ACCOUNT_PATH'].to_s.strip
        if creds_raw.empty?
          warn 'error: set EBAY_LISTINGS_COVERAGE_SEED_DIR (ebay_<mp>.txt), EBAY_LISTINGS_COVERAGE_SEED_FILE, ' \
               'or EBAY_LISTINGS_COVERAGE_ID_SOURCE=inventory, or set GCS_SERVICE_ACCOUNT_PATH to load ' \
               'EBAY_<MP>.txt from GCS in memory'
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
        query_opts[:seed_text_fetcher] = lambda do |mkt|
          blob_name = "#{prefix}/sources/EBAY_#{mkt.upcase}.txt"
          gcs.download_string(blob_name)
        end
      end
    end

    snapshot_time = Time.now.utc
    row = Em::Tools::EbayListingsCoverageQuery.new(**query_opts.merge(snapshot_time: snapshot_time)).fetch_row

    if inventory_mode
      err = row[:error] || row['error']
      unless err.nil? || err.to_s.strip.empty?
        warn "error: EbayListingsCoverageQuery failed: #{err}"
        exit 1
      end

      loaded = row[:seed_ids_loaded] || row['seed_ids_loaded']
      if loaded.to_i <= 0
        idx = row[:inventory_index] || row['inventory_index'] || ENV['EBAY_LISTINGS_COVERAGE_INVENTORY_INDEX']
        warn 'error: no eBay product ids loaded from inventory ' \
             "(inventory_index=#{idx.inspect}, seed_ids_loaded=#{loaded.inspect}). " \
             'Check EBAY_LISTINGS_COVERAGE_INVENTORY_SOURCE_TERMS, ' \
             'EBAY_LISTINGS_COVERAGE_INVENTORY_PRODUCT_ID_FIELD, ' \
             'and optional EBAY_LISTINGS_COVERAGE_INVENTORY_MARKETPLACE_FIELD.'
        exit 1
      end
    elsif query_opts[:seed_dir] || query_opts[:seed_text_fetcher] || !seed_file.empty?
      err = row[:error] || row['error']
      unless err.nil? || err.to_s.strip.empty?
        warn "error: EbayListingsCoverageQuery failed: #{err}"
        exit 1
      end

      loaded = row[:seed_ids_loaded] || row['seed_ids_loaded']
      if loaded.to_i <= 0
        warn 'error: no seed product ids loaded. Check EBAY_LISTINGS_COVERAGE_SEED_DIR / SEED_FILE / GCS EBAY_*.txt ' \
             'and that lines contain tab-separated JSON with source_product_id in column 2.'
        exit 1
      end
    end

    Em::Tools::EbayListingsCoverageSnapshot.persist!(
      [row],
      captured_at: snapshot_time,
      es_client: client,
      refresh: true
    )
    puts "Indexed eBay listings coverage snapshot (marketplace=#{mp.upcase}, index=#{row[:index_name]}) " \
         "-> #{Em::Tools::EbayListingsCoverageSnapshot.index_name}"
  end
end
# rubocop:enable Metrics/BlockLength
