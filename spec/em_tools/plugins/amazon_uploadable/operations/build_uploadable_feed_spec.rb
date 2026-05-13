# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::AmazonUploadable::Operations::BuildUploadableFeed) do
  let(:client) { instance_double(EmTools::Clients::ElasticsearchClient) }
  let(:sink) { RecordingSink.new }
  let(:logger) { instance_double(Logger, info: nil) }

  before do
    stub_const("RecordingSink", Class.new do
      attr_reader :records, :closed

      def initialize
        @records = []
        @closed = false
      end

      def index(record)
        @records << record
      end

      def close
        @closed = true
      end

      def stats
        { sink_written: @records.size }
      end

      def describe
        { kind: "recording" }
      end
    end)
  end

  it "builds feed rows from ASIN seeds and writes them to the injected sink" do
    allow(client).to(receive(:mget).with(index: "amz_products_api_de_v2", ids: ["B000000001"]).and_return(
      "docs" => [
        {
          "_id" => "B000000001",
          "found" => true,
          "_source" => {
            "asin" => "B000000001",
            "title" => "Test Product",
            "brand" => "Brand",
            "price" => 12.34,
            "currency" => "EUR",
          },
        },
      ],
    ))
    allow(client).to(receive(:index_exists?).with("lowest_offer_listings_de_new").and_return(true))
    allow(client).to(receive(:mget).with(index: "lowest_offer_listings_de_new", ids: ["B000000001"]).and_return(
      "docs" => [
        {
          "_id" => "B000000001",
          "found" => true,
          "_source" => { "price" => "19.99", "currency" => "EUR" },
        },
      ],
    ))

    result = described_class.new(
      marketplace: "de",
      source: ["B000000001"],
      sink: sink,
      client: client,
      listing_source: "AMZ_DE",
      source_code: "wholesale",
      store_code: "STORE",
      logger: logger,
    ).run!

    expect(result).to(include(asin_count: 1, product_count: 1, emitted_count: 1, sink_written: 1))
    expect(sink.records.first).to(include(
      "source" => "AMZ_DE",
      "source_code" => "wholesale",
      "source_product_id" => "B000000001",
      "store_code" => "STORE",
      "price" => 19.99,
      "currency" => "EUR",
    ))
    expect(sink.closed).to(be(true))
  end

  it "returns a manifest in dry-run mode without touching Elasticsearch" do
    expect(client).not_to(receive(:mget))

    manifest = described_class.new(
      marketplace: "us",
      source: ["B000000001"],
      sink: sink,
      client: client,
      dry_run: true,
      logger: logger,
    ).run!

    expect(manifest).to(include(marketplace: "us", product_index: "amz_products_api_us_v2"))
    expect(sink.closed).to(be(false))
  end
end
