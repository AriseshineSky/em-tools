# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Amazon::Uploadable::Sinks::UploadableFeedEs) do
  let(:client) { instance_double(EmTools::Clients::ElasticsearchClient) }

  it "bulk-indexes rows using source_product_id as the document id" do
    sink = described_class.new(client: client, index: "amz_uploadable_products_de", batch_size: 2, refresh: true)

    expect(client).to(receive(:bulk)) do |body:|
      lines = body.split("\n").reject(&:empty?)
      expect(lines.size).to(eq(4))
      expect(JSON.parse(lines.first).dig("index", "_id")).to(eq("B000000001"))
      { "errors" => false, "items" => [{ "index" => { "status" => 201 } }, { "index" => { "status" => 201 } }] }
    end
    expect(client).to(receive(:refresh).with("amz_uploadable_products_de"))

    sink.index("source_product_id" => "B000000001")
    sink.index("source_product_id" => "B000000002")
    sink.close

    expect(sink.stats).to(include(es_written: 2, es_bulk_requests: 1, es_bulk_errors: 0))
  end
end
