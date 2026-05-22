# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe(EmTools::Plugins::Ebay::Products::RedirectProductIdsExporter) do
  let(:es) { instance_double(EmTools::Clients::ElasticsearchClient) }

  before do
    allow(es).to(receive(:index_exists?).with("user1_ebay_products").and_return(true))
  end

  it "writes product_id for redirect=true and redirect_url containing /p/" do
    hits = [
      {
        "_id" => "113222835111",
        "_source" => {
          "product_id" => "113222835111",
          "redirect" => true,
          "redirect_url" => "https://www.ebay.com/p/12345",
        },
      },
      {
        "_id" => "999",
        "_source" => {
          "product_id" => "999",
          "redirect" => true,
          "redirect_url" => "https://www.ebay.com/itm/999",
        },
      },
      {
        "_id" => "888",
        "_source" => {
          "product_id" => "888",
          "redirect" => false,
          "redirect_url" => "https://www.ebay.com/p/ignored",
        },
      },
    ]
    allow(es).to(receive(:iterate_query)) do |**kwargs, &blk|
      expect(kwargs[:query]).to(eq({ term: { redirect: true } }))
      hits.each(&blk)
      hits.size
    end

    Dir.mktmpdir do |dir|
      path = File.join(dir, "ids.txt")
      summary = described_class.new(es_client: es, index: "user1_ebay_products").export!(path)

      expect(summary[:exported_ids]).to(eq(1))
      expect(File.read(path).split).to(eq(["113222835111"]))
    end
  end
end
