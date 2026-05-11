# frozen_string_literal: true

require "json"
require "spec_helper"

RSpec.describe(EmTools::Plugins::AmazonLowestOffer::Services::OfferService) do
  let(:fake_client) { FakeEsClient.new }

  it "defaults the offer_index to lowest_offer_listings_<mp>_<condition>" do
    svc = described_class.new(client: fake_client, marketplace: "us")
    expect(svc.offer_index).to(eq("lowest_offer_listings_us_new"))

    svc_used = described_class.new(client: fake_client, marketplace: "JP", condition: "used")
    expect(svc_used.offer_index).to(eq("lowest_offer_listings_jp_used"))
  end

  it "returns {} when the index does not exist" do
    fake_client.set_index_exists("lowest_offer_listings_us_new", false)
    svc = described_class.new(client: fake_client, marketplace: "us")
    expect(svc.get_offers(["B00TEST111"])).to(eq({}))
  end

  it "parses _source.offers JSON, applies the filter, attaches time, returns {asin => offer | nil}" do
    fake_client.set_index_exists("lowest_offer_listings_us_new", true)
    fake_client.set_mget_response(
      "lowest_offer_listings_us_new",
      [
        es_doc(
          "B00WIN",
          JSON.generate([
            { "price" => 5, "fba" => false },
            { "price" => 2, "fba" => false },
            { "price" => 9, "fba" => true },
          ]),
          "2024-01-01T00:00:00",
        ),
        es_doc("B00FAIL", JSON.generate([{ "price" => 100, "fba" => true }]), "2024-01-01T00:00:00"),
        not_found("B00MISS"),
      ],
    )

    fba_filter = EmTools::Plugins::AmazonLowestOffer::Filters::OfferFilter.new(
      fba: true, provider_type: "min", picked_count: 5,
    )
    svc = described_class.new(client: fake_client, marketplace: "us", filter: fba_filter)
    result = svc.get_offers(["B00WIN", "B00FAIL", "B00MISS"])

    expect(result["B00WIN"]).to(include("price" => 9, "fba" => true, "time" => "2024-01-01T00:00:00"))
    expect(result["B00FAIL"]).to(include("price" => 100, "fba" => true))
    expect(result).to(have_key("B00MISS"))
    expect(result["B00MISS"]).to(be_nil)
  end

  it "retries on non-Hash transient responses, then gives up cleanly" do
    fake_client.set_index_exists("lowest_offer_listings_us_new", true)
    fake_client.queue_mget_response("lowest_offer_listings_us_new", false)
    fake_client.queue_mget_response("lowest_offer_listings_us_new", false)
    fake_client.queue_mget_response("lowest_offer_listings_us_new", false)

    sleep_calls = []
    svc = described_class.new(
      client: fake_client,
      marketplace: "us",
      max_retries: 3,
      transient_delay: 0.01,
      sleeper: ->(s) { sleep_calls << s },
    )
    expect(svc.get_offers(["B00X"])).to(eq({}))
    expect(sleep_calls.size).to(eq(2)) # 3 attempts -> 2 inter-attempt sleeps
  end

  it "marks offers expired when expire_hour is configured and time is older than threshold" do
    fake_client.set_index_exists("lowest_offer_listings_us_new", true)
    old_time = (Time.now.utc - (10 * 3600)).strftime("%Y-%m-%dT%H:%M:%S")
    fake_client.set_mget_response(
      "lowest_offer_listings_us_new",
      [es_doc("B00OLD", JSON.generate([{ "price" => 1 }]), old_time)],
    )

    filter = EmTools::Plugins::AmazonLowestOffer::Filters::OfferFilter.new(
      provider_type: "min", expire_hour: 1,
    )
    svc = described_class.new(client: fake_client, marketplace: "us", filter: filter)
    result = svc.get_offers(["B00OLD"])
    expect(result["B00OLD"]["expired"]).to(be(true))
  end

  def es_doc(asin, offers_json, time)
    {
      "_id" => asin,
      "found" => true,
      "_source" => { "asin" => asin, "time" => time, "offers" => offers_json },
    }
  end

  def not_found(asin)
    { "_id" => asin, "found" => false }
  end
end

# Minimal Elasticsearch client double used by the OfferService specs above.
class FakeEsClient
  def initialize
    @indices = {}
    @mget_queue = Hash.new { |h, k| h[k] = [] }
    @mget_default = {}
  end

  def set_index_exists(index, exists)
    @indices[index] = exists
  end

  def set_mget_response(index, docs)
    @mget_default[index] = { "docs" => docs }
  end

  def queue_mget_response(index, response)
    @mget_queue[index] << response
  end

  def index_exists?(index)
    @indices.fetch(index, true)
  end

  def mget(index:, ids:, **)
    queue = @mget_queue[index]
    if queue.empty?
      @mget_default[index] || { "docs" => ids.map { |id| { "_id" => id, "found" => false } } }
    else
      queue.shift
    end
  end
end
