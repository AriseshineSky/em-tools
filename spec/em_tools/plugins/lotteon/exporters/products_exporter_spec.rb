# frozen_string_literal: true

require "json"
require "tmpdir"

require "spec_helper"

class LotteonProductsExporterSpecClient
  attr_reader :calls

  def initialize(docs)
    @docs = docs
    @calls = []
  end

  def iterate_all(index:, batch_size:, &block)
    @calls << { index: index, batch_size: batch_size }
    @docs.each(&block)
  end
end

RSpec.describe(EmTools::Plugins::Lotteon::Exporters::ProductsExporter) do
  it "writes NDJSON to a local file" do
    client = LotteonProductsExporterSpecClient.new([
      { "_id" => "1", "_source" => { "sku" => "A-1", "name" => "Alpha" } },
      { "_id" => "2", "_source" => { "sku" => "B-2", "name" => "Beta" } },
    ])

    Dir.mktmpdir do |dir|
      path = File.join(dir, "lotteon.ndjson")
      counts = described_class.new(client: client).to_jsonl(path, batch_size: 25)

      expect(counts).to(eq({ total: 2, written: 2, blocked: 0, filtered: 0 }))
      expect(File.read(path).lines.map(&:strip)).to(eq([
        JSON.generate("sku" => "A-1", "name" => "Alpha"),
        JSON.generate("sku" => "B-2", "name" => "Beta"),
      ]))
      expect(client.calls).to(eq([{ index: "user1_lotteon_products", batch_size: 25 }]))
    end
  end

  it "supports converter :skip and returns filtered count" do
    client = LotteonProductsExporterSpecClient.new([
      { "_source" => { "sku" => "skip-me" } },
      { "_source" => { "sku" => "keep" } },
    ])
    io = StringIO.new
    conv = proc { |src| src["sku"] == "skip-me" ? :skip : src }

    counts = described_class.new(client: client, converter: conv).write_jsonl(io, batch_size: 10)

    expect(counts).to(eq({ total: 2, written: 1, blocked: 0, filtered: 1 }))
    expect(JSON.parse(io.string.lines.first.chomp)["sku"]).to(eq("keep"))
  end
end
