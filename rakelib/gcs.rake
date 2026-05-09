# frozen_string_literal: true

namespace :gcs do
  desc 'Download AMZ marketplace seeds from GCS to tmp/amz_<mp>.txt'
  task :download_seeds do
    EmTools::Core::RakeSupport.run do
      creds_path = EmTools::Clients::GcsServiceAccountPath.require!
      target = File.join(File.expand_path('..', __dir__), 'tmp')

      EmTools::Plugins::AmazonLowestOffer::Sources::SeedFiles.sync_from_gcs(
        target,
        marketplaces: EmTools::Plugins::AmazonLowestOffer::Queries::ListingsCoverageQuery::DEFAULT_MARKETPLACES,
        creds_path: creds_path,
        bucket: ENV.fetch('GCS_BUCKET', 'em-bucket'),
        prefix: ENV.fetch('GCS_SEEDS_PREFIX', 'em-analytics'),
        force: true
      )
      EmTools::Core::RakeSupport::Result.new(
        summary: "Seeds synced to #{target} (GCS objects AMZ_<MP>.txt -> amz_<mp>.txt)"
      )
    end
  end
end
