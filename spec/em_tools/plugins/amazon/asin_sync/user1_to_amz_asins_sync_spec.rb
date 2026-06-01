# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Amazon::AsinSync::User1ToAmzAsinsSync) do
  let(:source) { instance_double(EmTools::Clients::ElasticsearchClient) }
  let(:target) { instance_double(EmTools::Clients::ElasticsearchClient) }

  it "indexes only ASINs missing from the target marketplace index" do
    sync = described_class.new(
      source_client: source,
      target_client: target,
      since_hours: 1,
      bulk_chunk: 2,
    )

    hits = [
      {
        "_id" => "AE_B0DCBCK799",
        "_source" => {
          "asin" => "B0DCBCK799",
          "marketplace" => "AE",
          "created_at" => "2026-05-29T06:06:50.473353+00:00",
        },
      },
      {
        "_id" => "DE_B07DCT7Q9T",
        "_source" => {
          "asin" => "B07DCT7Q9T",
          "marketplace" => "DE",
          "created_at" => "2026-02-26T22:53:29.483348+00:00",
        },
      },
    ]

    expect(source).to(receive(:iterate_query)) do |index:, query:, batch_size:, &block|
      expect(index).to(eq("user1_amz_asins"))
      expect(query).to(include(bool: hash_including(must: array_including(hash_including(range: hash_including("created_at"))))))
      hits.each(&block)
    end

    expect(target).to(receive(:index_exists?).with("amz_asins_ae").and_return(true))
    expect(target).to(receive(:mget).with(index: "amz_asins_ae", ids: ["B0DCBCK799"]).and_return(
      "docs" => [{ "_id" => "B0DCBCK799", "found" => false }],
    ))
    expect(target).to(receive(:index_exists?).with("amz_asins_de").and_return(true))
    expect(target).to(receive(:mget).with(index: "amz_asins_de", ids: ["B07DCT7Q9T"]).and_return(
      "docs" => [{ "_id" => "B07DCT7Q9T", "found" => true }],
    ))
    expect(target).to(receive(:bulk)) do |body:|
      expect(body).to(include('"asin":"B0DCBCK799"'))
      expect(body).to(include('"timestamp":"2026-05-29T06:06:50.473353+00:00"'))
      expect(body).not_to(include("B07DCT7Q9T"))
      { "errors" => false, "items" => [{ "index" => { "status" => 201 } }] }
    end

    stats = sync.run!
    expect(stats.source_hits).to(eq(2))
    expect(stats.skipped_existing).to(eq(1))
    expect(stats.indexed).to(eq(1))
  end

  it "scans the entire source index when full_scan is enabled" do
    sync = described_class.new(source_client: source, target_client: target, full_scan: true)

    expect(source).to(receive(:iterate_query)) do |index:, query:, **|
      expect(index).to(eq("user1_amz_asins"))
      expect(query).to(eq(match_all: {}))
    end
    expect(target).not_to(receive(:bulk))

    stats = sync.run!
    expect(stats.source_hits).to(eq(0))
  end
end
