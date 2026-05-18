# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe(EmTools::Core::Inventory::Sync) do
  it "uses ProductID as Elasticsearch _id (product_id)" do
    sink = instance_double(EmTools::Core::Sinks::ElasticsearchBulkSink, bulk: { "errors" => false })
    captured = nil
    allow(sink).to(receive(:bulk)) do |body:|
      captured = body
      { "errors" => false }
    end

    f = Tempfile.new(["amz_tr", ".csv"])
    f.write(<<~CSV)
      ProductID,Source,SourceProductID,Handle,Variants,InStock
      5872616,AMZ_TR,B07X7ZDJQB,rosy-drop,"[{""variant_id"":1}]",true
    CSV
    f.flush

    sync = described_class.new(sink: sink, index: "em_inventory")
    sync.sync_from_path(f.path)

    action = captured.first[:update]
    expect(action[:_id]).to(eq("5872616"))
    doc = action[:data][:doc]
    expect(doc["product_id"]).to(eq("5872616"))
    expect(doc["source"]).to(eq("AMZ_TR"))
    expect(doc["inventory_feed"]).to(eq("AMZ_TR"))
  end
end
