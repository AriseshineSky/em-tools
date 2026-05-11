# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::AmazonUploadable::Pipelines::AsinProductIndexPipeline) do
  let(:filter) { instance_double(EmTools::Plugins::AmazonUploadable::Filters::UploadableProductFilter) }
  let(:client) { instance_double(EmTools::Clients::ElasticsearchClient) }

  it "mgets products, filters by price, and bulk indexes" do
    hit = { "_id" => "B00GOOD001", "_source" => { "asin" => "B00GOOD001" } }
    expect(filter).to(receive(:each_asin_hit).with(hash_including(client: client, max_hits: nil)).and_yield(hit))

    expect(client).to(receive(:mget).with(
      index: "amz_products_api_us_v2",
      ids: ["B00GOOD001"],
    ).and_return(
      "docs" => [
        {
          "found" => true,
          "_id" => "B00GOOD001",
          "_source" => { "title" => "Nice product", "price" => "19.99" },
        },
      ],
    ))

    expect(client).to(receive(:bulk)) do |body:|
      expect(body).to(include("B00GOOD001"))
      expect(body).to(include('"asin":"B00GOOD001"'))
      { "errors" => false, "items" => [{ "index" => { "status" => 201 } }] }
    end

    pipeline = described_class.new(
      marketplace: "us",
      sink_index: "enriched_test",
      filter: filter,
      min_price: 10,
      max_price: 500,
    )
    stats = pipeline.run!(client: client, dry_run: false)
    expect(stats.accepted).to(eq(1))
    expect(stats.bulk_requests).to(eq(1))
    expect(stats.bulk_errors).to(eq(0))
  end

  it "rejects missing products" do
    hit = { "_id" => "B00MISSING", "_source" => {} }
    expect(filter).to(receive(:each_asin_hit).and_yield(hit))
    expect(client).to(receive(:mget).and_return(
      "docs" => [{ "found" => false, "_id" => "B00MISSING" }],
    ))
    expect(client).not_to(receive(:bulk))

    stats = described_class.new(marketplace: "us", sink_index: "enriched_test", filter: filter).run!(client: client)
    expect(stats.rejected_no_product).to(eq(1))
    expect(stats.accepted).to(eq(0))
  end

  it "respects dry_run without bulk" do
    hit = { "_id" => "B00GOOD001", "_source" => {} }
    expect(filter).to(receive(:each_asin_hit).and_yield(hit))
    expect(client).to(receive(:mget).and_return(
      "docs" => [{ "found" => true, "_id" => "B00GOOD001", "_source" => { "title" => "t", "price" => 9.0 } }],
    ))
    expect(client).not_to(receive(:bulk))

    stats = described_class.new(
      marketplace: "us",
      sink_index: "enriched_test",
      filter: filter,
      min_price: 1,
      max_price: 100,
    ).run!(client: client, dry_run: true)
    expect(stats.accepted).to(eq(1))
    expect(stats.bulk_requests).to(eq(0))
  end
end
