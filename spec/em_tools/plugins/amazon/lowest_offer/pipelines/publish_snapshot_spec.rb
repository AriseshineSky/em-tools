# frozen_string_literal: true

require "spec_helper"

# -- spec
RSpec.describe(EmTools::Plugins::Amazon::LowestOffer::Pipelines::PublishSnapshot) do
  let(:client) { instance_double(EmTools::Clients::ElasticsearchClient) }
  let(:snapshot_time) { Time.utc(2026, 5, 9, 0, 0, 0) }
  let(:now) { -> { snapshot_time } }
  let(:env) { {} }

  before do
    allow(EmTools::Plugins::Amazon::LowestOffer::Sinks::CoverageSnapshot).to(receive(:index_name).and_return("idx"))
  end

  context "when LOWEST_OFFER_ID_SOURCE=inventory" do
    let(:env) { { "LOWEST_OFFER_ID_SOURCE" => "inventory" } }

    it "runs the query without GCS / seed_dir and persists rows" do
      query = instance_double(EmTools::Plugins::Amazon::LowestOffer::Queries::ListingsCoverageQuery)
      rows = [{ marketplace: "US", seed_asins_loaded: 5 }]
      expect(EmTools::Plugins::Amazon::LowestOffer::Queries::ListingsCoverageQuery).to(receive(:new)
        .with(hash_including(es_client: client, snapshot_time: snapshot_time))
        .and_return(query))
      expect(query).to(receive(:fetch_all).and_return(rows))
      expect(EmTools::Plugins::Amazon::LowestOffer::Sinks::CoverageSnapshot).to(receive(:persist!)
        .with(rows, captured_at: snapshot_time, es_client: client, refresh: true))

      result = described_class.new(es_client: client, env: env, now: now).run!
      expect(result.summary).to(include("1 marketplace row"))
    end

    it "raises EmptyResultError when no ASINs loaded" do
      query = instance_double(EmTools::Plugins::Amazon::LowestOffer::Queries::ListingsCoverageQuery)
      allow(EmTools::Plugins::Amazon::LowestOffer::Queries::ListingsCoverageQuery).to(receive(:new).and_return(query))
      allow(query).to(receive(:fetch_all).and_return([{ marketplace: "US", seed_asins_loaded: 0 }]))

      expect do
        described_class.new(es_client: client, env: env, now: now).run!
      end.to(raise_error(EmTools::Core::Errors::EmptyResultError, /no Amazon ASINs loaded/))
    end
  end

  context "with seed_dir mode and missing GCS credentials" do
    let(:env) { { "LOWEST_OFFER_SEED_DIR" => "/nonexistent-seed-dir" } }

    it "raises ConfigurationError before running the query" do
      allow(EmTools::Plugins::Amazon::LowestOffer::Sources::SeedFiles).to(receive(:seed_file_present?).and_return(false))
      allow(EmTools::Clients::GcsServiceAccountPath).to(receive(:resolve).and_return("/no/key.json"))
      allow(File).to(receive(:file?).and_call_original)
      allow(File).to(receive(:file?).with("/no/key.json").and_return(false))

      expect do
        described_class.new(es_client: client, env: env, now: now).run!
      end.to(raise_error(EmTools::Core::Errors::ConfigurationError, /missing seed files/))
    end
  end

  context "when CLI marketplaces are provided" do
    it "forwards them lowercased to the query" do
      query = instance_double(EmTools::Plugins::Amazon::LowestOffer::Queries::ListingsCoverageQuery)
      expect(EmTools::Plugins::Amazon::LowestOffer::Queries::ListingsCoverageQuery).to(receive(:new)
        .with(hash_including(marketplaces: ["us", "ca"]))
        .and_return(query))
      allow(query).to(receive(:fetch_all).and_return([]))
      allow(EmTools::Plugins::Amazon::LowestOffer::Sinks::CoverageSnapshot).to(receive(:persist!))

      described_class.new(
        cli_marketplaces: "US, CA",
        es_client: client,
        env: { "LOWEST_OFFER_ID_SOURCE" => "inventory" },
        now: now,
      ).run!
    end
  end
end
