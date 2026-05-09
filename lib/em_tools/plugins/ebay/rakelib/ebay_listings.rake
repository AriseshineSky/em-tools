# frozen_string_literal: true

namespace :ebay_listings do
  desc 'Publish eBay listings coverage snapshot to ES. ' \
       'Sources: EBAY_LISTINGS_COVERAGE_ID_SOURCE=inventory | EBAY_LISTINGS_COVERAGE_SEED_FILE=path | ' \
       'EBAY_LISTINGS_COVERAGE_SEED_DIR=dir (ebay_<mp>.txt) | unset (in-memory GCS). ' \
       'Args: rake \'ebay_listings:publish_snapshot[us]\' or EBAY_LISTINGS_COVERAGE_MARKETPLACE.'
  task :publish_snapshot, [:marketplace] do |_t, args|
    EmTools::Core::RakeSupport.run do
      EmTools::Plugins::Ebay::Pipelines::PublishSnapshot.new(
        cli_marketplace: args[:marketplace]
      ).run!
    end
  end
end
