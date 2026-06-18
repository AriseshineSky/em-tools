# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Monitoring::Client) do
  let(:client) do
    described_class.new(
      base_url: "https://monitor.example.com",
      api_token: "secret-token",
      http: http,
    )
  end
  let(:http) { instance_double(Net::HTTP) }
  let(:response) { instance_double(Net::HTTPSuccess, is_a?: true) }

  before do
    allow(response).to(receive(:is_a?).with(Net::HTTPSuccess).and_return(true))
    allow(http).to(receive(:request).and_return(response))
  end

  describe "#configured?" do
    it "is true when base url and token are set" do
      expect(client.configured?).to(be(true))
    end

    it "is false when base url is missing" do
      expect(described_class.new(base_url: "", api_token: "x").configured?).to(be(false))
    end
  end

  describe "#post_inventory_sync_run" do
    it "posts JSON to the inventory sync endpoint" do
      expect(http).to(receive(:request) do |req|
        expect(req.path).to(eq("/api/v1/inventory_sync_runs"))
        expect(req["Authorization"]).to(eq("Bearer secret-token"))
        expect(JSON.parse(req.body)).to(include("source" => "AMZ_DE", "status" => "done"))
        response
      end)

      client.post_inventory_sync_run(source: "AMZ_DE", status: "done")
    end
  end

  describe "#post" do
    it "no-ops when not configured" do
      silent = described_class.new(base_url: "", api_token: "")
      expect(http).not_to(receive(:request))
      silent.post_inventory_sync_run(source: "AMZ_DE", status: "done")
    end
  end
end
