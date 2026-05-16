# frozen_string_literal: true

require "tmpdir"

require "spec_helper"

RSpec.describe(EmTools::Plugins::Amazon::LowestOffer::Queries::ListingsCoverageQuery) do
  let(:es_client) { instance_double(EmTools::Clients::ElasticsearchClient) }
  let(:snapshot_time) { Time.utc(2026, 1, 15, 12, 0, 0) }

  def activity_response
    {
      "hits" => { "total" => { "value" => 8 } },
      "aggregations" => {
        "missing_time" => { "doc_count" => 1 },
        "with_time" => {
          "windows" => {
            "buckets" => {
              "last_24h" => { "doc_count" => 1 },
              "hours_24_to_48_ago" => { "doc_count" => 2 },
              "hours_48_to_72h_ago" => { "doc_count" => 3 },
              "hours_72_to_96h_ago" => { "doc_count" => 4 },
              "hours_96_to_120h_ago" => { "doc_count" => 5 },
              "older_than_120h" => { "doc_count" => 6 },
              "at_or_after_now" => { "doc_count" => 7 },
              "other_time_window" => { "doc_count" => 8 },
            },
          },
        },
      },
    }
  end

  def coverage_response
    {
      "aggregations" => {
        "seed_asins_present" => {
          "buckets" => [{ "key" => "B000000001", "doc_count" => 1 }],
        },
      },
    }
  end

  it "aggregates freshness windows through 120h and older-than-120h" do
    calls = []
    allow(es_client).to(receive(:search)) do |args|
      calls << args
      calls.size == 1 ? activity_response : coverage_response
    end

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "amz_us.txt"), "x\t{\"source_product_id\":\"B000000001\"}\n")

      row = described_class.new(
        es_client: es_client,
        marketplaces: ["us"],
        snapshot_time: snapshot_time,
        seed_dir: dir,
      ).fetch_marketplace("us")

      expect(row).to(include(
        time_last_24h: 1,
        time_24_to_48h_ago: 2,
        time_48_to_72h_ago: 3,
        time_72_to_96h_ago: 4,
        time_96_to_120h_ago: 5,
        time_older_than_120h: 6,
        time_at_or_after_now: 7,
        time_other_window: 8,
        docs_missing_time: 1,
        time_activity_docs_sum: 37,
      ))
      expect(row).not_to(have_key(:time_older_than_72h))

      window_filters = calls.first.dig(:body, :aggs, :with_time, :aggs, :windows, :filters, :filters)
      expect(window_filters.keys).to(include(
        :last_24h,
        :hours_24_to_48_ago,
        :hours_48_to_72h_ago,
        :hours_72_to_96h_ago,
        :hours_96_to_120h_ago,
        :older_than_120h,
      ))
      expect(window_filters).not_to(have_key(:older_than_72h))
    end
  end
end
