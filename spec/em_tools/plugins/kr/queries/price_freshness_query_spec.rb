# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Kr::Queries::PriceFreshnessQuery) do
  let(:es_client) { instance_double(EmTools::Clients::ElasticsearchClient) }
  let(:snapshot_time) { Time.utc(2026, 6, 16, 12, 0, 0) }

  let(:loader) { instance_double(EmTools::Plugins::Ebay::Sources::InventoryProductIdLoader) }

  before do
    allow(EmTools::Plugins::Ebay::Sources::InventoryProductIdLoader).to(receive(:new).and_return(loader))
  end

  it "counts fresh vs stale products for inventory ids" do
    allow(loader).to(receive(:load).with("kr").and_return(%w[111 222 333]))

    expect(es_client).to(receive(:mget).with(
      index: "user1_kr_products",
      ids: %w[elevenst_111 elevenst_222 elevenst_333],
    ).and_return(
      "docs" => [
        {
          "_id" => "elevenst_111",
          "found" => true,
          "_source" => { "source" => "elevenst", "date" => "2026-06-15T12:00:00+00:00" },
        },
        {
          "_id" => "elevenst_222",
          "found" => true,
          "_source" => { "source" => "elevenst", "date" => "2026-06-01T12:00:00+00:00" },
        },
        { "_id" => "elevenst_333", "found" => false },
      ],
    ))

    row = described_class.new(
      es_client: es_client,
      snapshot_time: snapshot_time,
      threshold_days: 7,
      bulk_chunk: 10,
    ).fetch_row

    expect(row[:inventory_total]).to(eq(3))
    expect(row[:products_found]).to(eq(2))
    expect(row[:products_missing]).to(eq(1))
    expect(row[:fresh_within_threshold]).to(eq(1))
    expect(row[:stale_older_than_threshold]).to(eq(1))
    expect(row[:fresh_pct]).to(eq(50.0))
  end

  it "treats missing time as docs_missing_time" do
    allow(loader).to(receive(:load).with("kr").and_return(%w[111]))

    expect(es_client).to(receive(:mget).and_return(
      "docs" => [
        { "_id" => "elevenst_111", "found" => true, "_source" => { "source" => "elevenst" } },
      ],
    ))

    row = described_class.new(es_client: es_client, snapshot_time: snapshot_time, bulk_chunk: 10).fetch_row
    expect(row[:docs_missing_time]).to(eq(1))
    expect(row[:fresh_within_threshold]).to(eq(0))
  end
end
