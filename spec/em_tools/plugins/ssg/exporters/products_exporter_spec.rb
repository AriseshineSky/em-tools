# frozen_string_literal: true

require "json"
require "tmpdir"

require "spec_helper"

class SsgProductsExporterSpecClient
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

RSpec.describe(EmTools::Plugins::Ssg::Exporters::ProductsExporter) do
  it "writes NDJSON to a local file" do
    client = SsgProductsExporterSpecClient.new([
      { "_source" => { "sku" => "S-1", "name" => "Sigma" } },
      { "_source" => { "sku" => "S-2", "name" => "Tau" } },
    ])

    Dir.mktmpdir do |dir|
      path = File.join(dir, "ssg.ndjson")
      described_class.new(client: client).to_jsonl(path, batch_size: 17)

      expect(File.read(path).lines.map(&:strip)).to(eq([
        JSON.generate("sku" => "S-1", "name" => "Sigma"),
        JSON.generate("sku" => "S-2", "name" => "Tau"),
      ]))
      expect(client.calls).to(eq([{ index: "ssg_products", batch_size: 17 }]))
    end
  end
end
