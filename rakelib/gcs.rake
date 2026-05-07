# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength -- Rake DSL
namespace :gcs do
  desc 'Download AMZ marketplace seeds from GCS to tmp/gcs/amz_<mp>.txt'
  task :download_seeds do
    require 'em/tools'

    creds_path = Em::Tools::GcsServiceAccountPath.resolve
    unless File.file?(creds_path)
      if ENV['GCS_SERVICE_ACCOUNT_PATH'].to_s.strip.empty?
        warn "error: place your service account JSON at #{creds_path} or set GCS_SERVICE_ACCOUNT_PATH"
      else
        warn "error: GCS_SERVICE_ACCOUNT_PATH is not a file: #{creds_path}"
      end
      exit 1
    end

    bucket = ENV.fetch('GCS_BUCKET', 'em-bucket')
    prefix = ENV.fetch('GCS_SEEDS_PREFIX', 'em-analytics')
    root = File.expand_path('..', __dir__)
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
# rubocop:enable Metrics/BlockLength
