# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe(EmTools::Plugins::Ebay::ProductSync::User1ToEbayUsProductsSync) do
  let(:source) { instance_double(EmTools::Clients::ElasticsearchClient) }
  let(:target) { instance_double(EmTools::Clients::ElasticsearchClient) }

  let(:sample_source) do
    {
      "date" => "2026-05-18T14:45:15+00:00",
      "product_id" => "113222835111",
      "title" => "example",
      "existence" => true,
    }
  end

  it "upserts source documents into the target index by _id" do
    sync = described_class.new(
      source_client: source,
      target_client: target,
      since_date: "2026-05-01T00:00:00+00:00",
      bulk_chunk: 2,
    )

    hits = [
      { "_id" => "113222835111", "_source" => sample_source },
      { "_id" => "", "_source" => { "date" => "2026-05-18T14:45:15+00:00", "product_id" => "999" } },
      { "_id" => "abc123", "_source" => sample_source.merge("product_id" => "abc123") },
    ]

    expect(source).to(receive(:iterate_query)) do |index:, query:, batch_size:, &block|
      expect(index).to(eq("user1_ebay_products"))
      expect(query).to(include(bool: hash_including(filter: array_including(
        hash_including(range: hash_including("date" => hash_including(:gt))),
      ))))
      hits.each(&block)
    end

    expect(target).to(receive(:index_exists?).with("ebay_us_products").and_return(true))
    expect(target).to(receive(:mget).with(index: "ebay_us_products", ids: ["113222835111"]).and_return(
      "docs" => [{ "_id" => "113222835111", "found" => false }],
    ))
    expect(target).to(receive(:bulk)) do |body:|
      expect(body).to(include('"113222835111"'))
      expect(body).to(include('"title":"example"'))
      expect(body).not_to(include('"999"'))
      { "errors" => false, "items" => [{ "index" => { "status" => 201 } }] }
    end

    stats = sync.run!
    expect(stats.source_hits).to(eq(3))
    expect(stats.skipped_invalid).to(eq(2))
    expect(stats.indexed).to(eq(1))
  end

  it "updates only existing target docs when skip_missing is enabled" do
    sync = described_class.new(
      source_client: source,
      target_client: target,
      since_hours: 1,
      skip_missing: true,
      bulk_chunk: 10,
    )

    hits = [
      { "_id" => "111", "_source" => sample_source.merge("product_id" => "111") },
      { "_id" => "222", "_source" => sample_source.merge("product_id" => "222") },
    ]

    allow(source).to(receive(:iterate_query)) { |**, &block| hits.each(&block) }
    expect(target).to(receive(:index_exists?).with("ebay_us_products").and_return(true))
    expect(target).to(receive(:mget).with(index: "ebay_us_products", ids: ["111", "222"]).and_return(
      "docs" => [
        {
          "_id" => "111",
          "found" => true,
          "_source" => { "date" => "2026-05-01T00:00:00+00:00" },
        },
        { "_id" => "222", "found" => false },
      ],
    ))
    expect(target).to(receive(:bulk)) do |body:|
      expect(body).to(include('"111"'))
      expect(body).not_to(include('"222"'))
      { "errors" => false, "items" => [{ "index" => { "status" => 200 } }] }
    end

    stats = sync.run!
    expect(stats.skipped_missing).to(eq(1))
    expect(stats.indexed).to(eq(1))
  end

  it "writes _id and date checkpoint files every sample_interval indexed docs" do
    dir = File.expand_path("tmp/rspec_ebay_sync_samples_#{Process.pid}", Dir.pwd)
    FileUtils.mkdir_p(dir)

    sync = described_class.new(
      source_client: source,
      target_client: target,
      since_hours: 1,
      bulk_chunk: 10,
      sample_dir: dir,
      sample_interval: 2,
    )

    hits = (1..3).map do |n|
      {
        "_id" => n.to_s,
        "_source" => sample_source.merge(
          "product_id" => n.to_s,
          "date" => "2026-05-18T14:45:1#{n}+00:00",
        ),
      }
    end

    allow(source).to(receive(:iterate_query)) { |**, &block| hits.each(&block) }
    allow(target).to(receive(:index_exists?).with("ebay_us_products").and_return(true))
    allow(target).to(receive(:mget).and_return("docs" => []))
    allow(target).to(receive(:bulk).and_return(
      "errors" => false,
      "items" => [{ "index" => { "status" => 201 } }],
    ))

    stats = sync.run!
    expect(stats.indexed).to(eq(3))
    expect(stats.sample_files).to(eq(2))
    expect(stats.sample_rows).to(eq(3))

    batch1 = File.read(File.join(dir, "batch_001.tsv"))
    expect(batch1).to(include("_id\tdate"))
    expect(batch1).to(include("1\t2026-05-18T14:45:11+00:00"))
    expect(batch1).to(include("2\t2026-05-18T14:45:12+00:00"))
    expect(batch1).not_to(include("3\t"))

    batch2 = File.read(File.join(dir, "batch_002.tsv"))
    expect(batch2).to(include("3\t2026-05-18T14:45:13+00:00"))
  ensure
    FileUtils.rm_rf(dir) if dir && File.directory?(dir)
  end

  it "skips target docs that are newer than the source by time_field" do
    sync = described_class.new(
      source_client: source,
      target_client: target,
      since_hours: 1,
      bulk_chunk: 10,
    )

    hits = [
      {
        "_id" => "111",
        "_source" => sample_source.merge(
          "product_id" => "111",
          "date" => "2026-05-18T14:45:15+00:00",
        ),
      },
      {
        "_id" => "222",
        "_source" => sample_source.merge(
          "product_id" => "222",
          "date" => "2026-05-21T14:45:15+00:00",
        ),
      },
    ]

    allow(source).to(receive(:iterate_query)) { |**, &block| hits.each(&block) }
    expect(target).to(receive(:index_exists?).with("ebay_us_products").and_return(true))
    expect(target).to(receive(:mget).with(index: "ebay_us_products", ids: ["111", "222"]).and_return(
      "docs" => [
        {
          "_id" => "111",
          "found" => true,
          "_source" => { "date" => "2026-05-19T14:45:15+00:00" },
        },
        {
          "_id" => "222",
          "found" => true,
          "_source" => { "date" => "2026-05-20T14:45:15+00:00" },
        },
      ],
    ))
    expect(target).to(receive(:bulk)) do |body:|
      expect(body).not_to(include('"111"'))
      expect(body).to(include('"222"'))
      { "errors" => false, "items" => [{ "index" => { "status" => 200 } }] }
    end

    stats = sync.run!
    expect(stats.skipped_stale).to(eq(1))
    expect(stats.indexed).to(eq(1))
  end

  it "scans the entire source index when full_scan is enabled" do
    sync = described_class.new(source_client: source, target_client: target, full_scan: true)

    expect(source).to(receive(:iterate_query)) do |index:, query:, **|
      expect(index).to(eq("user1_ebay_products"))
      expect(query).to(eq(match_all: {}))
    end
    expect(target).not_to(receive(:bulk))

    stats = sync.run!
    expect(stats.source_hits).to(eq(0))
  end
end
