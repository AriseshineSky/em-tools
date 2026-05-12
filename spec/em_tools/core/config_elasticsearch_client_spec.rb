# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Config) do
  describe ".elasticsearch_client" do
    before do
      allow(EmTools::Clients::ElasticsearchClient).to(receive(:new))
    end

    it "uses an explicit url when given (wins over the env-resolved value)" do
      described_class.elasticsearch_client(url: "http://override:9200")
      expect(EmTools::Clients::ElasticsearchClient).to(have_received(:new).with(url: "http://override:9200"))
    end

    it "treats blank/whitespace url as 'no override' and resolves via the connection url" do
      allow(described_class).to(receive(:elasticsearch_connection_url)
        .with(prefer_data_cluster: false).and_return("http://primary:9200"))

      described_class.elasticsearch_client(url: "  ")

      expect(EmTools::Clients::ElasticsearchClient).to(have_received(:new).with(url: "http://primary:9200"))
    end

    it "asks for the data cluster when prefer_data_cluster: true" do
      allow(described_class).to(receive(:elasticsearch_connection_url)
        .with(prefer_data_cluster: true).and_return("http://data:9200"))

      described_class.elasticsearch_client(prefer_data_cluster: true)

      expect(EmTools::Clients::ElasticsearchClient).to(have_received(:new).with(url: "http://data:9200"))
    end

    it "resolves a named cluster: parameter via Config.cluster_url" do
      allow(described_class).to(receive(:cluster_url).with("data").and_return("http://data:9200"))

      described_class.elasticsearch_client(cluster: "data")

      expect(EmTools::Clients::ElasticsearchClient).to(have_received(:new).with(url: "http://data:9200"))
    end

    it "lets explicit url: win over a named cluster: parameter" do
      described_class.elasticsearch_client(url: "http://x:9200", cluster: "data")
      expect(EmTools::Clients::ElasticsearchClient).to(have_received(:new).with(url: "http://x:9200"))
    end
  end

  describe ".cluster_url" do
    around do |example|
      prev_primary = ENV.fetch("ELASTICSEARCH_URL", nil)
      prev_data = ENV.fetch("DATA_ELASTICSEARCH_URL", nil)
      example.run
    ensure
      prev_primary ? ENV["ELASTICSEARCH_URL"] = prev_primary : ENV.delete("ELASTICSEARCH_URL")
      prev_data ? ENV["DATA_ELASTICSEARCH_URL"] = prev_data : ENV.delete("DATA_ELASTICSEARCH_URL")
    end

    it "resolves nil/empty/'primary' to the primary URL" do
      ENV["ELASTICSEARCH_URL"] = "http://primary:9200"
      ENV.delete("DATA_ELASTICSEARCH_URL")

      expect(described_class.cluster_url(nil)).to(eq("http://primary:9200"))
      expect(described_class.cluster_url("")).to(eq("http://primary:9200"))
      expect(described_class.cluster_url("primary")).to(eq("http://primary:9200"))
    end

    it "resolves 'data' to DATA_ELASTICSEARCH_URL when set" do
      ENV["ELASTICSEARCH_URL"] = "http://primary:9200"
      ENV["DATA_ELASTICSEARCH_URL"] = "http://data:9200"

      expect(described_class.cluster_url("data")).to(eq("http://data:9200"))
      expect(described_class.cluster_url("analytics")).to(eq("http://data:9200"))
    end

    it "falls back to ELASTICSEARCH_URL for 'data' when DATA_ELASTICSEARCH_URL is unset and YAML has no entry" do
      ENV["ELASTICSEARCH_URL"] = "http://primary:9200"
      ENV.delete("DATA_ELASTICSEARCH_URL")
      allow(described_class).to(receive(:data_elasticsearch_url).and_return(nil))

      expect(described_class.cluster_url("data")).to(eq("http://primary:9200"))
    end

    it "raises ConfigurationError for unknown clusters that have no env / YAML entry" do
      ENV["ELASTICSEARCH_URL"] = "http://primary:9200"
      allow(described_class).to(receive(:elasticsearch_cluster_url).with("nope").and_return(nil))

      expect { described_class.cluster_url("nope") }
        .to(raise_error(EmTools::Core::Errors::ConfigurationError, /ES cluster "nope" not configured/))
    end
  end
end
