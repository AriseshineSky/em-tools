# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe(EmTools::Plugins::Ebay::Products::NonexistentProductIdsExporter) do
  let(:es) { instance_double(EmTools::Clients::ElasticsearchClient) }

  before do
    allow(es).to(receive(:index_exists?).with("user1_ebay_products").and_return(true))
  end

  it "writes product_id where existence is false" do
    hits = [
      {
        "_id" => "111",
        "_source" => { "product_id" => "111", "existence" => false },
      },
      {
        "_id" => "222",
        "_source" => { "product_id" => "222", "existence" => true },
      },
    ]
    allow(es).to(receive(:iterate_query)) do |**kwargs, &blk|
      expect(kwargs[:query]).to(eq({ term: { existence: false } }))
      hits.each(&blk)
      hits.size
    end

    Dir.mktmpdir do |dir|
      path = File.join(dir, "ids.txt")
      summary = described_class.new(es_client: es, index: "user1_ebay_products").export!(path)

      expect(summary[:exported_ids]).to(eq(1))
      expect(File.read(path).strip).to(eq("111"))
    end
  end
end
