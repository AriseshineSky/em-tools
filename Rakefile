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
  desc 'Download AMZ marketplace seeds from GCS to tmp/gcs/ebay_<mp>.txt'
  task :download_seeds do
    require 'em/tools'

    creds_path = Em::Tools::Config.gcs_service_account_path.to_s.strip
    if creds_path.empty?
      warn 'error: set GCS_SERVICE_ACCOUNT_PATH to your service account JSON file'
      exit 1
    end

    bucket = ENV.fetch('GCS_BUCKET', 'em-bucket')
    prefix = ENV.fetch('GCS_SEEDS_PREFIX', 'em-analytics').sub(%r{/+\z}, '')

    helper = Em::Tools::GcsHelper.new(creds_path, bucket, prefix)
    root = File.expand_path(__dir__)
    marketplaces = %w[US CA MX AE DE IN IT JP UK]

    marketplaces.each do |mp|
      blob_name = "#{prefix}/sources/AMZ_#{mp}.txt"
      local_path = File.join(root, 'tmp', 'gcs', "ebay_#{mp.downcase}.txt")
      puts "begin to download #{blob_name} -> #{local_path}"
      helper.download_file(blob_name, local_path)
      puts "downloaded #{blob_name} -> #{local_path}"
    end
  end
end

namespace :lowest_offer do
  desc 'Compute lowest-offer activity coverage and index snapshot to Elasticsearch'
  task :publish_snapshot do
    require 'em/tools'
    require 'time'

    client = Em::Tools::ElasticsearchClient.new
    rows = Em::Tools::LowestOfferListingsCoverageQuery.new(es_client: client).fetch_all
    Em::Tools::LowestOfferCoverageSnapshot.persist!(
      rows,
      captured_at: Time.now,
      es_client: client,
      refresh: true
    )
    puts "Indexed #{rows.size} marketplace rows -> #{Em::Tools::LowestOfferCoverageSnapshot.index_name}"
  end

  desc 'Download GCS seeds (gcs:download_seeds) then publish_snapshot'
  task download_and_publish: %w[gcs:download_seeds lowest_offer:publish_snapshot]
end

task default: %i[]
