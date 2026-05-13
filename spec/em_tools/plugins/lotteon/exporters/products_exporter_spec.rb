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
      { "_source" => { "sku" => "A-1", "name" => "Alpha" } },
      { "_source" => { "sku" => "B-2", "name" => "Beta" } },
    ])

    Dir.mktmpdir do |dir|
      path = File.join(dir, "lotteon.ndjson")
      described_class.new(client: client).to_jsonl(path, batch_size: 25)

      expect(File.read(path).lines.map(&:strip)).to(eq([
        JSON.generate("sku" => "A-1", "name" => "Alpha"),
        JSON.generate("sku" => "B-2", "name" => "Beta"),
      ]))
      expect(client.calls).to(eq([{ index: "user1_lotteon_products", batch_size: 25 }]))
    end
  end
end
