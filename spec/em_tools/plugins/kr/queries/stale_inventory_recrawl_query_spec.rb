# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Kr::Queries::StaleInventoryRecrawlQuery) do
  let(:es_client) { instance_double(EmTools::Clients::ElasticsearchClient) }
  let(:snapshot_time) { Time.utc(2026, 6, 29, 12, 0, 0) }
  let(:loader) { instance_double(EmTools::Plugins::Ebay::Sources::InventoryProductIdLoader) }

  before do
    allow(EmTools::Plugins::Ebay::Sources::InventoryProductIdLoader).to(receive(:new).and_return(loader))
  end

  it "returns stale and missing products with resolved URLs" do
    allow(loader).to(receive(:load).with("kr").and_return(%w[111 222 333]))

    expect(es_client).to(receive(:mget).with(
      index: "user1_kr_products",
      ids: %w[elevenst_111 elevenst_222 elevenst_333],
    ).and_return(
      "docs" => [
        {
          "_id" => "elevenst_111",
          "found" => true,
          "_source" => {
            "source" => "elevenst",
            "url" => "https://www.11st.co.kr/products/111",
            "updated_at" => "2026-06-28T12:00:00+00:00",
          },
        },
        {
          "_id" => "elevenst_222",
          "found" => true,
          "_source" => {
            "source" => "elevenst",
            "url" => "https://www.11st.co.kr/products/222",
            "updated_at" => "2026-06-01T12:00:00+00:00",
          },
        },
        { "_id" => "elevenst_333", "found" => false },
      ],
    ))

    stats = described_class.new(
      es_client: es_client,
      snapshot_time: snapshot_time,
      stale_days: 7,
      bulk_chunk: 10,
    ).fetch

    expect(stats[:inventory_total]).to(eq(3))
    expect(stats[:fresh_products]).to(eq(1))
    expect(stats[:stale_products]).to(eq(1))
    expect(stats[:missing_products]).to(eq(1))
    expect(stats[:recrawl_items].map(&:product_id)).to(eq(%w[222 333]))
    expect(stats[:recrawl_items].map(&:reason)).to(eq(%w[stale missing]))
    expect(stats[:recrawl_items].first.url).to(eq("https://www.11st.co.kr/products/222"))
    expect(stats[:recrawl_items].last.url).to(eq("https://www.11st.co.kr/products/333"))
  end

  it "treats missing updated_at as stale" do
    allow(loader).to(receive(:load).with("kr").and_return(%w[111]))

    expect(es_client).to(receive(:mget).and_return(
      "docs" => [
        {
          "_id" => "elevenst_111",
          "found" => true,
          "_source" => { "source" => "elevenst", "url" => "https://www.11st.co.kr/products/111" },
        },
      ],
    ))

    stats = described_class.new(es_client: es_client, snapshot_time: snapshot_time, bulk_chunk: 10).fetch
    expect(stats[:stale_products]).to(eq(1))
    expect(stats[:recrawl_items].size).to(eq(1))
  end
end
