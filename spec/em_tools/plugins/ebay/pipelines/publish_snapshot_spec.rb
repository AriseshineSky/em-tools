# frozen_string_literal: true

require "spec_helper"

# -- spec
RSpec.describe(EmTools::Plugins::Ebay::Pipelines::PublishSnapshot) do
  let(:client) { instance_double(EmTools::Clients::ElasticsearchClient) }
  let(:snapshot_time) { Time.utc(2026, 5, 9, 0, 0, 0) }
  let(:now) { -> { snapshot_time } }

  before do
    allow(EmTools::Plugins::Ebay::Sinks::CoverageSnapshot).to(receive(:index_name).and_return("ebay_idx"))
  end

  context "when EBAY_LISTINGS_COVERAGE_ID_SOURCE=inventory" do
    let(:env) { { "EBAY_LISTINGS_COVERAGE_ID_SOURCE" => "inventory" } }

    it "runs the query and persists a single row" do
      query = instance_double(EmTools::Plugins::Ebay::Queries::ListingsCoverageQuery)
      row = { marketplace: "US", seed_ids_loaded: 3, index_name: "ebay_us_products" }
      expect(EmTools::Plugins::Ebay::Queries::ListingsCoverageQuery).to(receive(:new)
        .with(hash_including(es_client: client, marketplace: "us", snapshot_time: snapshot_time))
        .and_return(query))
      expect(query).to(receive(:fetch_row).and_return(row))
      expect(EmTools::Plugins::Ebay::Sinks::CoverageSnapshot).to(receive(:persist!)
        .with([row], captured_at: snapshot_time, es_client: client, refresh: true))

      result = described_class.new(es_client: client, env: env, now: now).run!
      expect(result.summary).to(include("marketplace=US"))
      expect(result.summary).to(include("ebay_idx"))
    end

    it "raises EmptyResultError when seed_ids_loaded == 0" do
      query = instance_double(EmTools::Plugins::Ebay::Queries::ListingsCoverageQuery)
      allow(EmTools::Plugins::Ebay::Queries::ListingsCoverageQuery).to(receive(:new).and_return(query))
      allow(query).to(receive(:fetch_row).and_return({ marketplace: "US", seed_ids_loaded: 0 }))

      expect do
        described_class.new(es_client: client, env: env, now: now).run!
      end.to(raise_error(EmTools::Core::Errors::EmptyResultError, /no eBay product ids loaded/))
    end
  end

  context "with seed_file pointing at a missing path" do
    let(:env) { { "EBAY_LISTINGS_COVERAGE_SEED_FILE" => "/no/such/file.txt" } }

    it "raises ConfigurationError before running the query" do
      allow(File).to(receive(:file?).and_call_original)
      allow(File).to(receive(:file?).with(File.expand_path("/no/such/file.txt")).and_return(false))

      expect do
        described_class.new(es_client: client, env: env, now: now).run!
      end.to(raise_error(EmTools::Core::Errors::ConfigurationError, /SEED_FILE is not a file/))
    end
  end

  context "with explicit marketplace argument" do
    let(:env) { { "EBAY_LISTINGS_COVERAGE_ID_SOURCE" => "inventory" } }

    it "overrides the env-provided marketplace" do
      query = instance_double(EmTools::Plugins::Ebay::Queries::ListingsCoverageQuery)
      expect(EmTools::Plugins::Ebay::Queries::ListingsCoverageQuery).to(receive(:new)
        .with(hash_including(marketplace: "de"))
        .and_return(query))
      allow(query).to(receive(:fetch_row).and_return({ marketplace: "DE", seed_ids_loaded: 1, index_name: "i" }))
      allow(EmTools::Plugins::Ebay::Sinks::CoverageSnapshot).to(receive(:persist!))

      described_class.new(cli_marketplace: "DE", es_client: client, env: env, now: now).run!
    end
  end
end
