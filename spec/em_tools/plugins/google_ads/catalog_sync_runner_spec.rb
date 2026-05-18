# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Inventory::SyncRunner) do
  describe ".run_one_from_env! with Google Ads catalog profile" do
    let(:runner) { instance_double(described_class) }
    let(:profile) { EmTools::Plugins::GoogleAds::CatalogSyncProfile::PROFILE }
    let(:base_env) { { "ELASTICSEARCH_URL" => "http://primary:9200" } }

    before do
      allow(EmTools::Core::Sinks::ElasticsearchBulkSink).to(receive(:new).and_return(:sink_double))
      allow(EmTools::Core::Config).to(receive(:elasticsearch_client).and_return(:client_double))
      allow(described_class).to(receive_messages(fetcher_opts_from_env: {}, new: runner))
      allow(runner).to(receive(:run_one!))
    end

    it "passes GOOGLE_ADS_CATALOG_* env keys and google_ads_feed to run_one!" do
      env = base_env.merge(
        "GOOGLE_ADS_CATALOG_INDEX" => "google_ads_products",
        "GOOGLE_ADS_CATALOG_FEED_ID" => "google_ads_us",
        "GOOGLE_ADS_CATALOG_PRUNE_OBSOLETE" => "1",
      )

      described_class.run_one_from_env!(
        cli_gs_uri: "gs://b/google-ads.csv",
        env: env,
        profile: profile,
      )

      expect(runner).to(have_received(:run_one!).with(
        gs_uri: "gs://b/google-ads.csv",
        index: "google_ads_products",
        feed_id: "google_ads_us",
        refresh: false,
        prune_obsolete: true,
        drop_fields: [],
        feed_field: "google_ads_feed",
      ))
    end
  end
end
