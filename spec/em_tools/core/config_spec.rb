# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe(EmTools::Core::Config) do
  around do |example|
    prev_settings = ENV["EM_TOOLS_SETTINGS_PATH"]
    prev_app = ENV.fetch("APP_ENV", nil)
    prev_es = ENV.fetch("ELASTICSEARCH_URL", nil)
    example.run
    prev_settings ? ENV["EM_TOOLS_SETTINGS_PATH"] = prev_settings : ENV.delete("EM_TOOLS_SETTINGS_PATH")
    prev_app ? ENV["APP_ENV"] = prev_app : ENV.delete("APP_ENV")
    prev_es ? ENV["ELASTICSEARCH_URL"] = prev_es : ENV.delete("ELASTICSEARCH_URL")
    described_class.reload!
  end

  it "prefers ELASTICSEARCH_URL over YAML" do
    Tempfile.create(["cfg", ".yml"]) do |f|
      f.write(<<~YAML)
        default:
          elasticsearch:
            url: http://from-yaml:9200
        development: {}
      YAML
      f.flush
      ENV["EM_TOOLS_SETTINGS_PATH"] = f.path
      ENV["APP_ENV"] = "development"
      ENV["ELASTICSEARCH_URL"] = "http://from-env:9200"
      described_class.reload!
      expect(described_class.elasticsearch_url).to(eq("http://from-env:9200"))
    end
  end

  it "reads elasticsearch url from settings when ENV is unset" do
    Tempfile.create(["cfg", ".yml"]) do |f|
      f.write(<<~YAML)
        default:
          elasticsearch:
            url: http://yaml-only:9200
        development: {}
      YAML
      f.flush
      ENV["EM_TOOLS_SETTINGS_PATH"] = f.path
      ENV["APP_ENV"] = "development"
      ENV.delete("ELASTICSEARCH_URL")
      described_class.reload!
      expect(described_class.elasticsearch_url).to(eq("http://yaml-only:9200"))
    end
  end

  it "raises when elasticsearch url is nowhere to be found" do
    Tempfile.create(["cfg", ".yml"]) do |f|
      f.write("default: {}\ndevelopment: {}\n")
      f.flush
      ENV["EM_TOOLS_SETTINGS_PATH"] = f.path
      ENV["APP_ENV"] = "development"
      ENV.delete("ELASTICSEARCH_URL")
      described_class.reload!
      expect { described_class.elasticsearch_url }.to(raise_error(RuntimeError, /ELASTICSEARCH_URL/))
    end
  end

  it "exposes site() merged with env overrides" do
    Tempfile.create(["cfg", ".yml"]) do |f|
      f.write(<<~YAML)
        default:
          sites:
            acme:
              endpoint: https://yaml.example/api
              token: ""
        development: {}
      YAML
      f.flush
      ENV["EM_TOOLS_SETTINGS_PATH"] = f.path
      ENV["APP_ENV"] = "development"
      ENV["EM_TOOLS_SITE_ACME_TOKEN"] = "secret"
      described_class.reload!
      s = described_class.site("acme")
      expect(s["endpoint"]).to(eq("https://yaml.example/api"))
      expect(s["token"]).to(eq("secret"))
    end
  end

  describe ".elasticsearch_client_arguments" do
    after do
      ENV.delete("ELASTICSEARCH_API_KEY")
      ENV.delete("ELASTICSEARCH_USERNAME")
      ENV.delete("ELASTICSEARCH_PASSWORD")
      described_class.reload!
    end

    it "returns empty hash when no auth env is set" do
      expect(described_class.elasticsearch_client_arguments).to(eq({}))
    end

    it "returns api_key when ELASTICSEARCH_API_KEY is set" do
      ENV["ELASTICSEARCH_API_KEY"] = "encoded-key"
      described_class.reload!
      expect(described_class.elasticsearch_client_arguments).to(eq({ api_key: "encoded-key" }))
    end

    it "returns user and password when set" do
      ENV["ELASTICSEARCH_USERNAME"] = "u"
      ENV["ELASTICSEARCH_PASSWORD"] = "p"
      described_class.reload!
      expect(described_class.elasticsearch_client_arguments).to(eq({ user: "u", password: "p" }))
    end

    it "prefers api_key over username/password" do
      ENV["ELASTICSEARCH_API_KEY"] = "k"
      ENV["ELASTICSEARCH_USERNAME"] = "u"
      ENV["ELASTICSEARCH_PASSWORD"] = "p"
      described_class.reload!
      expect(described_class.elasticsearch_client_arguments).to(eq({ api_key: "k" }))
    end

    it "returns empty hash when url embeds credentials so global env does not override" do
      ENV["ELASTICSEARCH_USERNAME"] = "global"
      ENV["ELASTICSEARCH_PASSWORD"] = "wrong"
      described_class.reload!
      expect(described_class.elasticsearch_client_arguments(url: "http://a:b@localhost:9200")).to(eq({}))
    end
  end

  describe ".elasticsearch_connection_url" do
    around do |example|
      prev_primary = ENV["ELASTICSEARCH_URL"]
      prev_data = ENV["DATA_ELASTICSEARCH_URL"]
      example.run
      prev_primary.nil? ? ENV.delete("ELASTICSEARCH_URL") : ENV["ELASTICSEARCH_URL"] = prev_primary
      prev_data.nil? ? ENV.delete("DATA_ELASTICSEARCH_URL") : ENV["DATA_ELASTICSEARCH_URL"] = prev_data
      described_class.reload!
    end

    it "prefers DATA_ELASTICSEARCH_URL when prefer_data_cluster is true" do
      ENV["ELASTICSEARCH_URL"] = "http://primary:9200"
      ENV["DATA_ELASTICSEARCH_URL"] = "http://data:9200"
      described_class.reload!
      expect(described_class.elasticsearch_connection_url(prefer_data_cluster: true)).to(eq("http://data:9200"))
    end

    it "falls back to primary when prefer_data_cluster but DATA is unset" do
      Tempfile.create(["esconn", ".yml"]) do |f|
        f.write(<<~YAML)
          default:
            elasticsearch:
              url: http://primary:9200
            elasticsearch_clusters: {}
          development: {}
        YAML
        f.flush
        ENV["EM_TOOLS_SETTINGS_PATH"] = f.path
        ENV["APP_ENV"] = "development"
        ENV["ELASTICSEARCH_URL"] = "http://primary:9200"
        ENV.delete("DATA_ELASTICSEARCH_URL")
        described_class.reload!
        expect(described_class.elasticsearch_connection_url(prefer_data_cluster: true)).to(eq("http://primary:9200"))
      end
    end

    it "uses primary when prefer_data_cluster is false" do
      ENV["ELASTICSEARCH_URL"] = "http://primary:9200"
      ENV["DATA_ELASTICSEARCH_URL"] = "http://data:9200"
      described_class.reload!
      expect(described_class.elasticsearch_connection_url(prefer_data_cluster: false)).to(eq("http://primary:9200"))
    end
  end
end
