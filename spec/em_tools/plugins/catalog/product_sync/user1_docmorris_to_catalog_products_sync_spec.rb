# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe(EmTools::Plugins::Catalog::ProductSync::User1DocmorrisToCatalogProductsSync) do
  let(:source) { instance_double(EmTools::Clients::ElasticsearchClient) }
  let(:target) { instance_double(EmTools::Clients::ElasticsearchClient) }

  let(:sample_source) do
    {
      "date" => "2026-05-18T14:45:15+00:00",
      "product_id" => "07779825",
      "price" => 12.5,
      "shipping_fee" => 3.9,
      "currency" => "EUR",
      "available_qty" => 4,
      "existence" => true,
      "title" => "example",
      "categories" => ["health"],
    }
  end

  it "projects slim catalog docs and upserts by docmorris_{product_id}" do
    sync = described_class.new(
      source_client: source,
      target_client: target,
      since_date: "2026-05-01T00:00:00+00:00",
      bulk_chunk: 2,
    )

    hits = [
      { "_id" => "abc", "_source" => sample_source },
      { "_id" => "x", "_source" => { "date" => "2026-05-18T14:45:15+00:00" } },
    ]

    expect(source).to(receive(:iterate_query)) do |index:, query:, batch_size:, &block|
      expect(index).to(eq("user1_de_products"))
      expect(query).to(include(bool: hash_including(filter: array_including(
        { term: { "source.keyword" => "docmorris" } },
        hash_including(range: hash_including("date" => hash_including(:gt))),
      ))))
      hits.each(&block)
    end

    expect(target).to(receive(:index_exists?).with("catalog_products").and_return(true).at_least(:once))
    expect(target).to(receive(:mget).with(index: "catalog_products", ids: ["docmorris_07779825"]).and_return(
      "docs" => [{ "_id" => "docmorris_07779825", "found" => false }],
    ))
    expect(target).to(receive(:bulk)) do |body:|
      expect(body).to(include('"docmorris_07779825"'))
      expect(body).to(include('"source":"docmorris"'))
      expect(body).to(include('"product_id":"07779825"'))
      expect(body).to(include('"title":"example"'))
      expect(body).to(include('"extras"'))
      expect(body).to(include('"categories"'))
      { "errors" => false, "items" => [{ "index" => { "status" => 201 } }] }
    end

    stats = sync.run!
    expect(stats.source_hits).to(eq(2))
    expect(stats.skipped_invalid).to(eq(1))
    expect(stats.indexed).to(eq(1))
  end

  it "skips stale target docs when source date is older" do
    sync = described_class.new(
      source_client: source,
      target_client: target,
      since_hours: 1,
      bulk_chunk: 10,
      dry_run: true,
    )

    hits = [
      { "_id" => "1", "_source" => sample_source.merge("date" => "2026-05-01T00:00:00+00:00") },
    ]

    allow(source).to(receive(:iterate_query)) { |**, &block| hits.each(&block) }
    expect(target).to(receive(:index_exists?).with("catalog_products").and_return(true).at_least(:once))
    expect(target).to(receive(:mget).with(index: "catalog_products", ids: ["docmorris_07779825"]).and_return(
      "docs" => [
        {
          "_id" => "docmorris_07779825",
          "found" => true,
          "_source" => { "date" => "2026-05-18T00:00:00+00:00" },
        },
      ],
    ))
    expect(target).not_to(receive(:bulk))

    stats = sync.run!
    expect(stats.skipped_stale).to(eq(1))
    expect(stats.indexed).to(eq(0))
  end

  it "source_row_to_catalog_doc builds expected _id and core fields" do
    sync = described_class.new(source_client: source, target_client: target, dry_run: true)
    row = sync.source_row_to_catalog_doc(sample_source)
    expect(row[:doc_id]).to(eq("docmorris_07779825"))
    expect(row[:body]["source"]).to(eq("docmorris"))
    expect(row[:body]["marketplace"]).to(eq("de"))
    expect(row[:body]["currency"]).to(eq("EUR"))
    expect(row[:body]["extras"]["categories"]).to(eq(["health"]))
  end
end
