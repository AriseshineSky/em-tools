# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe(EmTools::Plugins::Amazon::Uploadable::Exporters::TopCategoryAsinExporter) do
  let(:es) { instance_double(EmTools::Clients::ElasticsearchClient) }

  before do
    allow(es).to(receive(:index_exists?).with("amz_products_api_de_v2").and_return(true))
  end

  it "writes one file per top_category with ASINs" do
    hits = [
      {
        "_id" => "B001",
        "_source" => {
          "asin" => "B001",
          "top_category" => "Health & Personal Care",
          "categories" => [{ "cat_name" => "Health & Personal Care", "cat_id" => "64187031" }],
        },
      },
      {
        "_id" => "B002",
        "_source" => {
          "asin" => "B002",
          "top_category" => "Health & Personal Care",
        },
      },
      {
        "_id" => "B003",
        "_source" => {
          "asin" => "B003",
          "top_category" => "Electronics",
        },
      },
    ]
    allow(es).to(receive(:iterate_query)) do |**_kwargs, &blk|
      hits.each(&blk)
      hits.size
    end

    Dir.mktmpdir do |dir|
      summary = described_class.new(
        es_client: es,
        product_index: "amz_products_api_de_v2",
        output_dir: dir,
      ).export!

      expect(summary[:asins]).to(eq(3))
      expect(summary[:categories]).to(eq(2))

      health = File.join(dir, "Health_&_Personal_Care.txt")
      expect(File.read(health).split).to(contain_exactly("B001", "B002"))

      electronics = File.join(dir, "Electronics.txt")
      expect(File.read(electronics).strip).to(eq("B003"))

      manifest = JSON.parse(File.read(File.join(dir, "manifest.json")))
      expect(manifest["categories"].map { |c| c["name"] }).to(include("Health & Personal Care", "Electronics"))
    end
  end

  describe ".query_for_categories" do
    it "uses bool should for multiple categories" do
      q = described_class.query_for_categories(["Beauty", "Health & Personal Care"])
      expect(q).to(eq(
        bool: {
          should: [
            { term: { top_category: "Beauty" } },
            { term: { top_category: "Health & Personal Care" } },
          ],
          minimum_should_match: 1,
        },
      ))
    end
  end
end
