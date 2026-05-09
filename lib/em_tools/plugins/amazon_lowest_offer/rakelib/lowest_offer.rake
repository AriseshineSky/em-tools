# frozen_string_literal: true

namespace :lowest_offer do
  desc 'Publish lowest-offer snapshot to ES (index monitoring_lowest_offer_snapshots). ' \
       'Sources: LOWEST_OFFER_ID_SOURCE=inventory (em_inventory) | LOWEST_OFFER_SEED_DIR=tmp ' \
       '(./tmp/amz_<mp>.txt; auto-downloads missing files from GCS, LOWEST_OFFER_SEEDS_FORCE_DOWNLOAD=1) | ' \
       'unset (in-memory GCS, needs GCS_SERVICE_ACCOUNT_PATH). ' \
       'Args: rake \'lowest_offer:publish_snapshot[us,ca]\' (defaults to LOWEST_OFFER_MARKETPLACES or 9 markets).'
  task :publish_snapshot, [:marketplaces] do |_t, args|
    EmTools::Core::RakeSupport.run do
      EmTools::Plugins::AmazonLowestOffer::Pipelines::PublishSnapshot.new(
        cli_marketplaces: args[:marketplaces]
      ).run!
    end
  end

  desc 'Download GCS seeds (gcs:download_seeds) then publish_snapshot'
  task download_and_publish: %w[gcs:download_seeds lowest_offer:publish_snapshot]
end
