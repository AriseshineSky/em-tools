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

  it "applies an optional converter to each written line after policy checks" do
    priced = [
      { "_source" => { "sku" => "A", "original_price" => 100 } },
      { "_source" => { "sku" => "B", "original_price" => 200 } },
    ]
    client = OliveyoungProductsExporterSpecClient.new(priced)
    converter = proc do |src|
      src.merge("sale_price" => (src["original_price"].to_f * 0.9).round(2))
    end
    io = StringIO.new

    described_class.new(client: client, converter: converter).write_jsonl(io, batch_size: 10)

    lines = io.string.lines.map { |l| JSON.parse(l) }
    expect(lines).to(eq([
      { "sku" => "A", "original_price" => 100, "sale_price" => 90.0 },
      { "sku" => "B", "original_price" => 200, "sale_price" => 180.0 },
    ]))
  end

  describe "keyword exclusion policy" do
    let(:mixed_docs) do
      [
        { "_id" => "1", "_source" => { "sku" => "OK-1", "title" => "shampoo bottle", "brand" => "BrandA" } },
        { "_id" => "2", "_source" => { "sku" => "BAD-1", "title" => "weed lotion",  "brand" => "BrandB" } },
        { "_id" => "3", "_source" => { "sku" => "OK-2", "title" => "face mask",     "brand" => "BrandC" } },
      ]
    end
    let(:policy) do
      EmTools::Core::Blacklist.build(
        keywords: ["weed"],
        rules_source: "product_download",
      )
    end

    it "drops blocked docs and writes them to the side-file" do
      client = OliveyoungProductsExporterSpecClient.new(mixed_docs)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "oy.ndjson")
        blocked = File.join(dir, "oy.blocked.ndjson")

        counts = described_class.new(
          client: client,
          policy: policy,
          blocked_output_path: blocked,
        ).to_jsonl(path, batch_size: 5)

        expect(counts).to(eq({ total: 3, written: 2, blocked: 1, filtered: 0 }))
        written_lines = File.read(path).lines.map(&:strip)
        expect(written_lines.length).to(eq(2))
        expect(written_lines.map { |l| JSON.parse(l)["sku"] }).to(eq(["OK-1", "OK-2"]))

        blocked_records = File.read(blocked).lines.map { |l| JSON.parse(l) }
        expect(blocked_records.length).to(eq(1))
        expect(blocked_records.first).to(include(
          "_id" => "2",
          "title" => "weed lotion",
          "matched" => ["weed"],
        ))
      end
    end

    it "runs keyword policy on raw source, converter only on written rows" do
      client = OliveyoungProductsExporterSpecClient.new(mixed_docs)
      converter = proc { |src| src.merge("title_en" => "translated-#{src["title"]}") }

      Dir.mktmpdir do |dir|
        path = File.join(dir, "oy.ndjson")
        blocked = File.join(dir, "oy.blocked.ndjson")

        described_class.new(
          client: client,
          policy: policy,
          blocked_output_path: blocked,
          converter: converter,
        ).to_jsonl(path, batch_size: 5)

        written = File.read(path).lines.map { |l| JSON.parse(l) }
        expect(written.map { |h| h["title_en"] }).to(eq(["translated-shampoo bottle", "translated-face mask"]))

        blocked_records = File.read(blocked).lines.map { |l| JSON.parse(l) }
        expect(blocked_records.first["title"]).to(eq("weed lotion"))
        expect(blocked_records.first).not_to(have_key("title_en"))
      end
    end

    it "skips the side-file when none is requested but still drops blocked docs" do
      client = OliveyoungProductsExporterSpecClient.new(mixed_docs)
      io = StringIO.new

      counts = described_class.new(client: client, policy: policy).write_jsonl(io, batch_size: 5)

      expect(counts).to(eq({ total: 3, written: 2, blocked: 1, filtered: 0 }))
      expect(io.string.lines.length).to(eq(2))
    end

    it "omits lines when the converter returns :skip" do
      client = OliveyoungProductsExporterSpecClient.new(mixed_docs)
      io = StringIO.new
      converter = proc do |src|
        src["sku"] == "OK-1" ? :skip : src
      end

      counts = described_class.new(client: client, policy: policy, converter: converter).write_jsonl(io, batch_size: 5)

      expect(counts).to(eq({ total: 3, written: 1, blocked: 1, filtered: 1 }))
      expect(io.string.lines.map { |l| JSON.parse(l)["sku"] }).to(eq(["OK-2"]))
    end
  end
end
