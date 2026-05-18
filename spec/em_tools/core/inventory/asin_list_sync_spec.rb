# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe(EmTools::Core::Inventory::AsinListSync) do
  let(:sink) { instance_double(EmTools::Core::Sinks::ElasticsearchBulkSink, bulk: { "errors" => false }) }

  it "indexes each ASIN line with _id = asin and source AMZ_DE" do
    captured = []
    allow(sink).to(receive(:bulk)) { |body:| captured.concat(body); { "errors" => false } }

    f = Tempfile.new(["seed", ".txt"])
    f.write("# seeds\nB07X7ZDJQB\nB083KN3V59\n")
    f.flush

    described_class.new(
      sink: sink,
      index: "google_ads_products",
      source_key: "AMZ_DE",
      feed_field: "google_ads_feed",
    ).sync_from_path(f.path)

    expect(captured.size).to(eq(2))
    first = captured.first[:update]
    expect(first[:_id]).to(eq("B07X7ZDJQB"))
    doc = first[:data][:doc]
    expect(doc["source_product_id"]).to(eq("B07X7ZDJQB"))
    expect(doc["source"]).to(eq("AMZ_DE"))
    expect(doc["google_ads_feed"]).to(eq("AMZ_DE"))
  end

  it "infers AMZ_DE from gs uri basename" do
    expect(described_class.infer_source_from_gs_uri("gs://em-bucket/em-analytics/sources/AMZ_DE.txt")).to(eq("AMZ_DE"))
  end
end
