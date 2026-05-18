# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe(EmTools::Core::Inventory::TabJsonLineSync) do
  let(:sink) { instance_double(EmTools::Core::Sinks::ElasticsearchBulkSink, bulk: { "errors" => false }) }

  it "uses product_id from JSON as _id and stores parsed fields" do
    captured = []
    allow(sink).to(receive(:bulk)) { |body:| captured.concat(body); { "errors" => false } }

    json = {
      product_id: 29_497_910,
      source: "AMZ_DE",
      source_product_id: "B0F6SZGFZQ",
      source_product_url: "https://www.amazon.de/dp/B0F6SZGFZQ",
      handle: "electric-callus-remover",
    }.to_json

    f = Tempfile.new(["feed", ".txt"])
    f.write("ignored\t#{json}\n")
    f.flush

    described_class.new(
      sink: sink,
      index: "google_ads_products",
      feed_field: "google_ads_feed",
      feed_id: "AMZ_DE",
    ).sync_from_path(f.path)

    action = captured.first[:update]
    expect(action[:_id]).to(eq("29497910"))
    doc = action[:data][:doc]
    expect(doc["product_id"]).to(eq(29_497_910))
    expect(doc["source_product_id"]).to(eq("B0F6SZGFZQ"))
    expect(doc["google_ads_feed"]).to(eq("AMZ_DE"))
    expect(doc["source_product_id"]).not_to(include("{"))
  end
end
