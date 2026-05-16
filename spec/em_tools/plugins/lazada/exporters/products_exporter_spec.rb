# frozen_string_literal: true

require "json"
require "spec_helper"

class LazadaProductsExporterSpecClient
  attr_reader :calls

  def initialize(docs)
    @docs = docs
    @calls = []
  end

  def iterate_query(index:, query:, batch_size:, &block)
    @calls << { index: index, query: query, batch_size: batch_size }
    @docs.each(&block)
  end
end

RSpec.describe(EmTools::Plugins::Lazada::Exporters::ProductsExporter) do
  let(:docs) do
    [{ "_source" => { "product_id" => "1", "title" => "A" } }]
  end

  let(:query) { { match_all: {} } }

  it "uses iterate_query with explicit index and query" do
    client = LazadaProductsExporterSpecClient.new(docs)
    idx = EmTools::Core::Config.exporter_index("lazada_th_products", "user1_lazadacoth_products")

    described_class.new(client: client, index: idx, query: query).to_jsonl(File::NULL, batch_size: 5)

    expect(client.calls.first[:index]).to(eq(idx))
    expect(client.calls.first[:query]).to(eq({ match_all: {} }))
  end

  it "accepts a ProductsQuery instance" do
    client = LazadaProductsExporterSpecClient.new(docs)
    q = EmTools::Plugins::Lazada::Queries::ProductsQuery.new(source_value: "lazadacoth")

    described_class.new(client: client, index: "user1_lazadacoth_products", query: q).each(batch_size: 3) { |_| }

    expect(client.calls.first[:query]).to(eq({
      bool: { filter: [{ term: { source: "lazadacoth" } }] },
    }))
  end
end
