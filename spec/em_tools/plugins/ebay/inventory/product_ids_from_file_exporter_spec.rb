# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe(EmTools::Plugins::Ebay::Inventory::ProductIdsFromFileExporter) do
  let(:es) { instance_double(EmTools::Clients::ElasticsearchClient) }

  before do
    allow(es).to(receive(:index_exists?).with("user1_ebay_us_products").and_return(true))
  end

  it "writes inventory product_id for matching source_product_id" do
    input = File.join(Dir.tmpdir, "ebay_ids_#{Process.pid}.txt")
    File.write(input, "113222835111\n999\n")

    allow(es).to(receive(:search)) do |body:, **|
      expect(body.dig(:query, :bool, :filter)).to(include(
        { terms: { "source.keyword" => ["Ebay_US", "EBAY_US", "ebay_us"] } },
        { terms: { "source_product_id.keyword" => ["113222835111", "999"] } },
      ))
      {
        "hits" => {
          "hits" => [
            {
              "_source" => {
                "source_product_id" => "113222835111",
                "product_id" => "inv-113222835111",
              },
            },
          ],
        },
      }
    end

    Dir.mktmpdir do |dir|
      out = File.join(dir, "product_ids.txt")
      summary = described_class.new(es_client: es, source: "Ebay_US", index: "user1_ebay_us_products").export!(
        input_path: input,
        output_path: out,
      )

      expect(summary[:matched_rows]).to(eq(1))
      expect(File.read(out).strip).to(eq("inv-113222835111"))
    end
  ensure
    File.delete(input) if File.file?(input)
  end
end
