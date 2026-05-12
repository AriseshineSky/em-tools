# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Inventory::SyncRunner) do
  describe ".run_from_settings!" do
    def make_source(uri:, cluster: nil, index: "inv")
      EmTools::Core::Inventory::SyncSources::Source.new(
        gs_uri: uri, index: index, refresh: false, feed_id: nil, prune_obsolete: false, cluster: cluster,
      )
    end

    let(:sources) { [make_source(uri: "gs://b/x.csv")] }

    before do
      stub_const("EmTools::Core::Sinks::ElasticsearchBulkSink", Class.new { def initialize(_ = nil) = nil })
      allow(EmTools::Core::Config).to(receive(:elasticsearch_client).and_return(:client_double))
    end

    it "raises ConfigurationError when ELASTICSEARCH_URL is missing" do
      expect do
        described_class.run_from_settings!(env: { "ELASTICSEARCH_URL" => "" })
      end.to(raise_error(EmTools::Core::Errors::ConfigurationError, /ELASTICSEARCH_URL/))
    end

    it "translates SyncSources::Error to ConfigurationError" do
      env = { "ELASTICSEARCH_URL" => "http://x" }
      allow(EmTools::Core::Inventory::SyncSources).to(receive(:load!)
        .and_raise(EmTools::Core::Inventory::SyncSources::Error.new("nope")))

      expect do
        described_class.run_from_settings!(env: env)
      end.to(raise_error(EmTools::Core::Errors::ConfigurationError, "nope"))
    end

    it "expands the explicit config_path and includes it in the summary" do
      env = { "ELASTICSEARCH_URL" => "http://x" }
      received_path = nil
      allow(EmTools::Core::Inventory::SyncSources).to(receive(:load!)) do |path|
        received_path = path
        sources
      end
      runner = instance_double(described_class, run_many!: EmTools::Core::Cli::Runner::Result.new(summary: "ok"))
      allow(described_class).to(receive(:new).and_return(runner))

      result = described_class.run_from_settings!(config_path: "config/x.yml", env: env)

      expect(received_path).to(eq(File.expand_path("config/x.yml")))
      expect(result.summary).to(include(File.expand_path("config/x.yml")))
      expect(result.summary).to(include("1 source(s)"))
    end

    it "falls back to the default settings path label when config_path is blank" do
      env = { "ELASTICSEARCH_URL" => "http://x" }
      received_path = :unset
      allow(EmTools::Core::Inventory::SyncSources).to(receive(:load!)) do |path|
        received_path = path
        sources
      end
      runner = instance_double(described_class, run_many!: EmTools::Core::Cli::Runner::Result.new(summary: "ok"))
      allow(described_class).to(receive(:new).and_return(runner))

      result = described_class.run_from_settings!(env: env)

      expect(received_path).to(be_nil)
      expect(result.summary).to(include(EmTools::Core::SettingsLoader.default_path))
    end

    context "when sources declare different clusters" do
      let(:mixed_sources) do
        [
          make_source(uri: "gs://b/a.csv", cluster: "primary"),
          make_source(uri: "gs://b/b.csv", cluster: "data"),
          make_source(uri: "gs://b/c.csv", cluster: "data"),
        ]
      end

      let(:env) { { "ELASTICSEARCH_URL" => "http://primary", "DATA_ELASTICSEARCH_URL" => "http://data" } }

      before do
        allow(EmTools::Core::Inventory::SyncSources).to(receive(:load!).and_return(mixed_sources))
      end

      it "builds one sink per distinct cluster and dispatches each group to its own runner" do
        runner = instance_double(described_class, run_many!: EmTools::Core::Cli::Runner::Result.new(summary: "ok"))
        allow(described_class).to(receive(:new).and_return(runner))

        described_class.run_from_settings!(env: env)

        expect(EmTools::Core::Config).to(have_received(:elasticsearch_client).with(cluster: "primary").once)
        expect(EmTools::Core::Config).to(have_received(:elasticsearch_client).with(cluster: "data").once)
        expect(runner).to(have_received(:run_many!).with(
          [mixed_sources[0]], label: nil
        ))
        expect(runner).to(have_received(:run_many!).with(
          [mixed_sources[1], mixed_sources[2]], label: nil
        ))
      end

      it "emits a per-cluster breakdown in the summary" do
        runner = instance_double(described_class, run_many!: EmTools::Core::Cli::Runner::Result.new(summary: "ok"))
        allow(described_class).to(receive(:new).and_return(runner))

        result = described_class.run_from_settings!(env: env)

        expect(result.summary).to(match(/3 source\(s\)/))
        expect(result.summary).to(match(/data=2/))
        expect(result.summary).to(match(/primary=1/))
      end
    end

    context "when prefer_data_cluster is true and a source has no explicit cluster" do
      let(:no_cluster_sources) { [make_source(uri: "gs://b/x.csv", cluster: nil)] }
      let(:env) { { "ELASTICSEARCH_URL" => "http://primary", "DATA_ELASTICSEARCH_URL" => "http://data" } }

      before do
        allow(EmTools::Core::Inventory::SyncSources).to(receive(:load!).and_return(no_cluster_sources))
      end

      it "uses the data cluster as the runtime default" do
        runner = instance_double(described_class, run_many!: EmTools::Core::Cli::Runner::Result.new(summary: "ok"))
        allow(described_class).to(receive(:new).and_return(runner))

        described_class.run_from_settings!(env: env, prefer_data_cluster: true)

        expect(EmTools::Core::Config).to(have_received(:elasticsearch_client).with(cluster: "data"))
      end
    end

    context "when prefer_data_cluster is true but a source pins cluster: primary" do
      let(:pinned_sources) { [make_source(uri: "gs://b/x.csv", cluster: "primary")] }
      let(:env) { { "ELASTICSEARCH_URL" => "http://primary", "DATA_ELASTICSEARCH_URL" => "http://data" } }

      before do
        allow(EmTools::Core::Inventory::SyncSources).to(receive(:load!).and_return(pinned_sources))
      end

      it "still routes that source to primary (per-source cluster wins)" do
        runner = instance_double(described_class, run_many!: EmTools::Core::Cli::Runner::Result.new(summary: "ok"))
        allow(described_class).to(receive(:new).and_return(runner))

        described_class.run_from_settings!(env: env, prefer_data_cluster: true)

        expect(EmTools::Core::Config).to(have_received(:elasticsearch_client).with(cluster: "primary"))
        expect(EmTools::Core::Config).not_to(have_received(:elasticsearch_client).with(cluster: "data"))
      end
    end
  end
end
