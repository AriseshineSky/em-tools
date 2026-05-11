# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe(EmTools::Core::Sinks::IndexDumper) do
  let(:client) { instance_double(EmTools::Clients::ElasticsearchClient) }
  let(:hits) do
    [
      { "_id" => "a", "_source" => { "title" => "apple", "brand" => "Acme" } },
      { "_id" => "b", "_source" => { "title" => "Bonafide vitamin", "brand" => "X" } },
      { "_id" => "c", "_source" => { "title" => "banana", "brand" => "Acme" } },
    ]
  end

  before { EmTools::Core::Logger.silent! }

  def stub_iterate_all(*items)
    allow(client).to(receive(:iterate_all).with(index: "my_idx", batch_size: 100)) do |&block|
      items.each(&block)
    end
  end

  it "streams every hit's _source to NDJSON and reports the count" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "sub", "dump.ndjson")
      stub_iterate_all(hits[0], hits[2])

      result = described_class.new(es_client: client, index: "my_idx", output_path: out, batch_size: 100).run!

      lines = File.readlines(out, chomp: true)
      expect(lines.size).to(eq(2))
      expect(JSON.parse(lines[0])).to(eq(hits[0]["_source"]))
      expect(result.summary).to(include("Wrote 2 hits to #{out}"))
    end
  end

  it "defaults output to tmp/<index>.ndjson when output_path is nil" do
    dumper = described_class.new(es_client: client, index: "my_idx")
    expect(dumper.instance_variable_get(:@output_path)).to(eq(File.join("tmp", "my_idx.ndjson")))
  end

  describe "with a policy" do
    let(:blacklist_policy) { EmTools::Core::Blacklist::Strategy::TitleBrand.new(["bonafide"]) }

    it "drops rejected hits and surfaces both counts in the summary" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "dump.ndjson")
        blocked = File.join(dir, "blocked.ndjson")
        stub_iterate_all(*hits)

        result = described_class.new(
          es_client: client,
          index: "my_idx",
          output_path: out,
          batch_size: 100,
          policy: blacklist_policy,
          blocked_output_path: blocked,
        ).run!

        kept = File.readlines(out, chomp: true).map { |l| JSON.parse(l) }
        expect(kept.map { |s| s["title"] }).to(contain_exactly("apple", "banana"))

        blocked_records = File.readlines(blocked, chomp: true).map { |l| JSON.parse(l) }
        expect(blocked_records.size).to(eq(1))
        expect(blocked_records.first).to(include(
          "_id" => "b",
          "title" => "Bonafide vitamin",
          "matched" => ["bonafide"],
        ))

        expect(result.summary).to(include("Wrote 2 hits to #{out}"))
        expect(result.summary).to(include("blocked 1/3"))
        expect(result.summary).to(include("1 blacklist keyword(s)"))
        expect(result.summary).to(include(blocked))
      end
    end

    it "skips writing the blocked side-file when nothing is rejected" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "dump.ndjson")
        blocked = File.join(dir, "blocked.ndjson")
        stub_iterate_all(hits[0], hits[2])

        result = described_class.new(
          es_client: client,
          index: "my_idx",
          output_path: out,
          batch_size: 100,
          policy: blacklist_policy,
          blocked_output_path: blocked,
        ).run!

        expect(File.exist?(blocked)).to(be(true)) # we always create it (truncated/empty)
        expect(File.size(blocked)).to(eq(0))
        expect(result.summary).not_to(include("->"))
      end
    end

    it "accepts a minimal policy (just #blocked?) and skips the side-file extras" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "dump.ndjson")
        bare_policy = Class.new do
          def blocked?(source) = source["title"] == "Bonafide vitamin"
        end.new
        stub_iterate_all(*hits)

        result = described_class.new(
          es_client: client, index: "my_idx", output_path: out, batch_size: 100, policy: bare_policy,
        ).run!

        expect(File.readlines(out, chomp: true).size).to(eq(2))
        expect(result.summary).to(include("blocked 1/3"))
        expect(result.summary).not_to(include("blacklist keyword(s)"))
      end
    end
  end
end
