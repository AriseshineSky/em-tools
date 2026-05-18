# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe(EmTools::Plugins::Amazon::Uploadable::Exporters::InventoryAsinsByTopCategoryExporter) do
  let(:es) { instance_double(EmTools::Clients::ElasticsearchClient) }

  before do
    allow(es).to(receive(:index_exists?).with("em_inventory").and_return(true))
    allow(es).to(receive(:index_exists?).with("amz_products_api_de_v2").and_return(true))
  end

  it "scrolls inventory by source and groups ASINs by top_category" do
    allow(es).to(receive(:iterate_query).with(
      hash_including(index: "em_inventory"),
    ).and_yield(
      "_source" => { "source" => "amz_de", "source_product_id" => "B001" },
    ).and_yield(
      "_source" => { "source" => "amz_de", "source_product_id" => "B002" },
    ))

    allow(es).to(receive(:mget).with(
      index: "amz_products_api_de_v2",
      ids: %w[B001 B002],
    ).and_return(
      "docs" => [
        { "_id" => "B001", "found" => true, "_source" => { "top_category" => "Beauty" } },
        { "_id" => "B002", "found" => true, "_source" => { "top_category" => "Beauty" } },
      ],
    ))

    Dir.mktmpdir do |dir|
      summary = described_class.new(
        es_client: es,
        source: "amz_de",
        marketplace: "de",
        output_dir: dir,
      ).export!

      expect(summary[:asins]).to(eq(2))
      expect(summary[:inventory_source]).to(eq("amz_de"))
      expect(File.read(File.join(dir, "de", "Beauty", "asins.txt")).strip.split("\n")).to(eq(%w[B001 B002]))
    end
  end

  it "infers marketplace from amz_<mp> source token" do
    expect(described_class.marketplace_from_source("amz_de")).to(eq("de"))
    expect(described_class.marketplace_from_source("AMZ_UK")).to(eq("uk"))
  end
end
