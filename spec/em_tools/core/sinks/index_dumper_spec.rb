# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe(EmTools::Core::Sinks::IndexDumper) do
  let(:client) { instance_double(EmTools::Clients::ElasticsearchClient) }
  let(:hits) do
    [
      { "_id" => "a", "_source" => { "name" => "apple" } },
      { "_id" => "b", "_source" => { "name" => "banana" } },
    ]
  end

  it "streams every hit to NDJSON and reports the count" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "sub", "dump.ndjson")
      allow(client).to(receive(:iterate_all)
        .with(index: "my_idx", batch_size: 100)
        .and_yield(hits[0]).and_yield(hits[1]))

      result = described_class.new(es_client: client, index: "my_idx", output_path: out, batch_size: 100).run!

      lines = File.readlines(out, chomp: true)
      expect(lines.size).to(eq(2))
      expect(JSON.parse(lines[0])).to(eq(hits[0]))
      expect(result.summary).to(include("Wrote 2 hits to #{out}"))
    end
  end

  it "defaults output to tmp/<index>.ndjson when output_path is nil" do
    dumper = described_class.new(es_client: client, index: "my_idx")
    expect(dumper.instance_variable_get(:@output_path)).to(eq(File.join("tmp", "my_idx.ndjson")))
  end
end
