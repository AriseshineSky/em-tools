# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe(EmTools::Plugins::Amazon::Uploadable::Exporters::AsinsByTopCategoryExporter) do
  let(:es) { instance_double(EmTools::Clients::ElasticsearchClient) }

  before do
    allow(es).to(receive(:index_exists?).with("amz_products_api_de_v2").and_return(true))
  end

  it "writes marketplace/top_category/asins.txt from mget top_category" do
    allow(es).to(receive(:mget).with(
      index: "amz_products_api_de_v2",
      ids: %w[B001 B002 B003],
    ).and_return(
      "docs" => [
        {
          "_id" => "B001",
          "found" => true,
          "_source" => { "top_category" => "Health & Personal Care" },
        },
        { "_id" => "B002", "found" => false },
        {
          "_id" => "B003",
          "found" => true,
          "_source" => { "top_category" => "Electronics" },
        },
      ],
    ))

    Dir.mktmpdir do |dir|
      input = File.join(dir, "in.txt")
      File.write(input, "B001\nB002\nB003\n")

      out_root = File.join(dir, "out")
      summary = described_class.new(
        es_client: es,
        product_index: "amz_products_api_de_v2",
        output_dir: out_root,
        marketplace: "de",
      ).export!(input_path: input)

      expect(summary[:asins]).to(eq(3))
      expect(summary[:missing]).to(eq(1))
      expect(summary[:categories]).to(eq(3))

      health = File.join(out_root, "de", "Health & Personal Care", "asins.txt")
      expect(File.read(health).strip).to(eq("B001"))

      unc = File.join(out_root, "de", "Uncategorized", "asins.txt")
      expect(File.read(unc).strip).to(eq("B002"))

      elec = File.join(out_root, "de", "Electronics", "asins.txt")
      expect(File.read(elec).strip).to(eq("B003"))
    end
  end

  it "infers marketplace from AMZ_<MP>.txt filename" do
    expect(described_class.marketplace_from_sold_filename("tmp/sold_asin/AMZ_UK.txt")).to(eq("uk"))
    expect(described_class.marketplace_from_sold_filename("AMZ_DE.txt")).to(eq("de"))
  end
end
