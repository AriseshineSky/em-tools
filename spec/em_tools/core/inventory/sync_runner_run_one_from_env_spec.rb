# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Inventory::SyncRunner) do
  describe ".run_one_from_env!" do
    let(:runner) { instance_double(described_class) }
    let(:base_env) { { "ELASTICSEARCH_URL" => "http://primary:9200" } }

    before do
      allow(EmTools::Core::Sinks::ElasticsearchBulkSink).to(receive(:new).and_return(:sink_double))
      allow(EmTools::Core::Config).to(receive(:elasticsearch_client).and_return(:client_double))
      allow(described_class).to(receive_messages(fetcher_opts_from_env: {}, new: runner))
      allow(runner).to(receive(:run_one!))
    end

    it "validates ELASTICSEARCH_URL is set when prefer_data_cluster is false" do
      expect do
        described_class.run_one_from_env!(env: { "ELASTICSEARCH_URL" => "" })
      end.to(raise_error(EmTools::Core::Errors::ConfigurationError, /ELASTICSEARCH_URL/))
    end

    it "accepts a missing ELASTICSEARCH_URL when DATA_ELASTICSEARCH_URL is set and prefer_data_cluster: true" do
      env = { "DATA_ELASTICSEARCH_URL" => "http://data:9200" }
      expect do
        described_class.run_one_from_env!(env: env, prefer_data_cluster: true)
      end.not_to(raise_error)
    end

    it "raises when neither URL is set and prefer_data_cluster: true" do
      expect do
        described_class.run_one_from_env!(env: {}, prefer_data_cluster: true)
      end.to(raise_error(EmTools::Core::Errors::ConfigurationError, /DATA_ELASTICSEARCH_URL/))
    end

    it "builds the sink against the data cluster when prefer_data_cluster: true" do
      env = base_env.merge("DATA_ELASTICSEARCH_URL" => "http://data:9200")
      described_class.run_one_from_env!(cli_gs_uri: "gs://b/x.csv", env: env, prefer_data_cluster: true)

      expect(EmTools::Core::Config).to(have_received(:elasticsearch_client).with(prefer_data_cluster: true))
      expect(EmTools::Core::Sinks::ElasticsearchBulkSink).to(have_received(:new).with(:client_double))
    end

    it "passes the resolved gs_uri + INVENTORY_* knobs through to run_one!" do
      env = base_env.merge(
        "INVENTORY_INDEX" => "ebay_us_products",
        "INVENTORY_FEED_ID" => "ebay",
        "INVENTORY_REFRESH" => "1",
        "INVENTORY_PRUNE_OBSOLETE" => "1",
      )

      described_class.run_one_from_env!(cli_gs_uri: "gs://b/ebay.csv", env: env)

      expect(runner).to(have_received(:run_one!).with(
        gs_uri: "gs://b/ebay.csv",
        index: "ebay_us_products",
        feed_id: "ebay",
        refresh: true,
        prune_obsolete: true,
        drop_fields: [],
        feed_field: "inventory_feed",
      ))
    end

    it "falls back to gs_uri as feed_id when INVENTORY_FEED_ID is blank" do
      described_class.run_one_from_env!(cli_gs_uri: "gs://b/x.csv", env: base_env)
      expect(runner).to(have_received(:run_one!).with(hash_including(feed_id: "gs://b/x.csv")))
    end

    it "parses INVENTORY_DROP_FIELDS as a comma-separated list and forwards it" do
      env = base_env.merge("INVENTORY_DROP_FIELDS" => "handle, variants ,")
      described_class.run_one_from_env!(cli_gs_uri: "gs://b/x.csv", env: env)
      expect(runner).to(have_received(:run_one!).with(hash_including(drop_fields: ["handle", "variants"])))
    end

    it "forwards an empty drop_fields list when INVENTORY_DROP_FIELDS is unset" do
      described_class.run_one_from_env!(cli_gs_uri: "gs://b/x.csv", env: base_env)
      expect(runner).to(have_received(:run_one!).with(hash_including(drop_fields: [])))
    end

    it "returns a Cli::Runner::Result with a summary that includes the gs_uri" do
      result = described_class.run_one_from_env!(cli_gs_uri: "gs://b/x.csv", env: base_env)
      expect(result).to(be_a(EmTools::Core::Cli::Runner::Result))
      expect(result.summary).to(include("gs://b/x.csv"))
    end
  end

  describe ".run_from_settings! prefer_data_cluster" do
    before do
      stub_const("EmTools::Core::Sinks::ElasticsearchBulkSink", Class.new { def initialize(_ = nil) = nil })
      allow(EmTools::Core::Config).to(receive(:elasticsearch_client).and_return(:client_double))
    end

    it "treats --data as the runtime default cluster for sources without a cluster:" do
      env = { "DATA_ELASTICSEARCH_URL" => "http://data:9200" }
      sources = [
        EmTools::Core::Inventory::SyncSources::Source.new(
          gs_uri: "gs://b/x.csv",
          index: "i",
          refresh: false,
          feed_id: nil,
          prune_obsolete: false,
          cluster: nil,
          drop_fields: [],
        ),
      ]
      allow(EmTools::Core::Inventory::SyncSources).to(receive(:load!).and_return(sources))
      runner = instance_double(described_class, run_many!: EmTools::Core::Cli::Runner::Result.new(summary: "ok"))
      allow(described_class).to(receive(:new).and_return(runner))

      described_class.run_from_settings!(env: env, prefer_data_cluster: true)

      expect(EmTools::Core::Config).to(have_received(:elasticsearch_client).with(cluster: "data"))
    end
  end
end
