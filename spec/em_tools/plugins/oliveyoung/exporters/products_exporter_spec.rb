# frozen_string_literal: true

require "json"
require "tmpdir"

require "spec_helper"

class OliveyoungProductsExporterSpecClient
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

RSpec.describe(EmTools::Plugins::Oliveyoung::Exporters::ProductsExporter) do
  let(:docs) do
    [
      { "_source" => { "sku" => "OY-1", "source" => "oliveyoung" } },
      { "_source" => { "sku" => "OY-2", "source" => "oliveyoung" } },
    ]
  end

  it "writes NDJSON, scoped to source=oliveyoung via iterate_query" do
    client = OliveyoungProductsExporterSpecClient.new(docs)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "oliveyoung.ndjson")
      described_class.new(client: client).to_jsonl(path, batch_size: 17)

      expect(File.read(path).lines.map(&:strip)).to(eq([
        JSON.generate("sku" => "OY-1", "source" => "oliveyoung"),
        JSON.generate("sku" => "OY-2", "source" => "oliveyoung"),
      ]))
      expect(client.calls).to(eq([{
        index: "oliveyoung_products",
        query: { bool: { filter: [{ term: { source: "oliveyoung" } }] } },
        batch_size: 17,
      }]))
    end
  end

  it "accepts a custom query (Hash or anything responding to #to_h)" do
    client = OliveyoungProductsExporterSpecClient.new(docs)
    custom_query = EmTools::Plugins::Oliveyoung::Queries::ProductsQuery.new(source_value: "OLIVEYOUNG")

    described_class.new(client: client, query: custom_query).each(batch_size: 5) { |_| }

    expect(client.calls.first[:query])
      .to(eq({ bool: { filter: [{ term: { source: "OLIVEYOUNG" } }] } }))
  end

  it "accepts a raw Hash query without a #to_h hop" do
    client = OliveyoungProductsExporterSpecClient.new(docs)
    raw = { match_all: {} }

    described_class.new(client: client, query: raw).each(batch_size: 5) { |_| }

    expect(client.calls.first[:query]).to(eq(raw))
  end
end
