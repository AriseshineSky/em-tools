# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe(EmTools::Core::Inventory::Sync) do
  it "writes google_ads_feed when feed_field is configured" do
    sink = instance_double(EmTools::Core::Sinks::ElasticsearchBulkSink, bulk: { "errors" => false })
    captured = nil
    allow(sink).to(receive(:bulk)) do |body:|
      captured = body
      { "errors" => false }
    end

    f = Tempfile.new(["gads", ".csv"])
    f.write("ProductID,Source\na,GoogleAds_US\n")
    f.flush

    sync = described_class.new(sink: sink, index: "google_ads_products", feed_field: "google_ads_feed")
    sync.sync_from_path(f.path)

    doc = captured.first[:update][:data][:doc]
    expect(doc["google_ads_feed"]).to(eq("GoogleAds_US"))
    expect(doc).not_to(have_key("inventory_feed"))
  end
end
