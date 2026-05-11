# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::AmazonUploadable::Filters::UploadableProductFilter) do
  let(:client) { instance_double(EmTools::Clients::ElasticsearchClient) }

  def hit(asin, source_extra = {})
    { "_id" => asin, "_source" => { "asin" => asin }.merge(source_extra) }
  end

  describe "#default_sink_index" do
    it "derives the sink index name from the marketplace" do
      filter = described_class.new(marketplace: "de")
      expect(filter.default_sink_index).to(eq("amz_uploadable_asins_de"))
    end
  end

  describe "#bulk_index_asins!" do
    it "bulk-indexes matched ASINs to the default sink index" do
      filter = described_class.new(marketplace: "us")

      allow(filter).to(receive(:each_asin_hit)) do |**, &block|
        block.call(hit("B00AAA", "timestamp" => "2026-05-01T00:00:00Z"))
        block.call(hit("B00BBB"))
      end

      captured_body = nil
      expect(client).to(receive(:bulk)) do |body:|
        captured_body = body
        { "errors" => false, "items" => [{ "index" => { "status" => 201 } }, { "index" => { "status" => 201 } }] }
      end

      stats = filter.bulk_index_asins!(client: client)

      expect(stats.asin_hits_seen).to(eq(2))
      expect(stats.asin_ids_indexed).to(eq(2))
      expect(stats.bulk_requests).to(eq(1))
      expect(stats.bulk_errors).to(eq(0))

      lines = captured_body.split("\n").reject(&:empty?)
      action_lines = lines.each_slice(2).map(&:first).map { |l| JSON.parse(l) }
      doc_lines = lines.each_slice(2).map(&:last).map { |l| JSON.parse(l) }

      expect(action_lines.map { |a| a.dig("index", "_index") }).to(all(eq("amz_uploadable_asins_us")))
      expect(action_lines.map { |a| a.dig("index", "_id") }).to(eq(["B00AAA", "B00BBB"]))
      expect(doc_lines.first).to(include("asin" => "B00AAA", "marketplace" => "us"))
      expect(doc_lines.first["source_time_value"]).to(eq("2026-05-01T00:00:00Z"))
    end

    it "respects the explicit sink_index override" do
      filter = described_class.new(marketplace: "us")
      allow(filter).to(receive(:each_asin_hit).and_yield(hit("B00AAA")))

      expect(client).to(receive(:bulk)) do |body:|
        first_action = JSON.parse(body.split("\n").first)
        expect(first_action.dig("index", "_index")).to(eq("custom_sink"))
        { "errors" => false, "items" => [{ "index" => { "status" => 201 } }] }
      end

      filter.bulk_index_asins!(client: client, sink_index: "custom_sink")
    end

    it "flushes in chunks based on bulk_chunk_lines" do
      filter = described_class.new(marketplace: "us")
      allow(filter).to(receive(:each_asin_hit)) do |**, &block|
        ["B0A", "B0B", "B0C", "B0D", "B0E"].each { |a| block.call(hit(a)) }
      end

      call_count = 0
      allow(client).to(receive(:bulk)) do |body:|
        call_count += 1
        items = body.split("\n").reject(&:empty?).count / 2
        { "errors" => false, "items" => Array.new(items) { { "index" => { "status" => 201 } } } }
      end

      stats = filter.bulk_index_asins!(client: client, bulk_chunk_lines: 2)

      expect(call_count).to(eq(3))
      expect(stats.bulk_requests).to(eq(3))
      expect(stats.asin_ids_indexed).to(eq(5))
    end

    it "deduplicates ASINs seen multiple times" do
      filter = described_class.new(marketplace: "us")
      allow(filter).to(receive(:each_asin_hit)) do |**, &block|
        block.call(hit("B0A"))
        block.call(hit("B0A"))
        block.call(hit("B0B"))
      end

      expect(client).to(receive(:bulk).once) do |body:|
        ids = body.split("\n").reject(&:empty?).each_slice(2).map { |l, _| JSON.parse(l).dig("index", "_id") }
        expect(ids).to(eq(["B0A", "B0B"]))
        { "errors" => false, "items" => Array.new(2) { { "index" => { "status" => 201 } } } }
      end

      stats = filter.bulk_index_asins!(client: client)
      expect(stats.asin_hits_seen).to(eq(3))
      expect(stats.asin_ids_indexed).to(eq(2))
    end

    it "skips bulk in dry_run mode but still counts hits" do
      filter = described_class.new(marketplace: "us")
      allow(filter).to(receive(:each_asin_hit).and_yield(hit("B0A")))
      expect(client).not_to(receive(:bulk))

      stats = filter.bulk_index_asins!(client: client, dry_run: true)
      expect(stats.asin_hits_seen).to(eq(1))
      expect(stats.bulk_requests).to(eq(0))
    end

    it "refreshes the sink index when refresh: true and not dry_run" do
      filter = described_class.new(marketplace: "us")
      allow(filter).to(receive(:each_asin_hit).and_yield(hit("B0A")))
      allow(client).to(receive(:bulk).and_return("errors" => false, "items" => [{ "index" => { "status" => 201 } }]))
      expect(client).to(receive(:refresh).with("amz_uploadable_asins_us"))

      filter.bulk_index_asins!(client: client, refresh: true)
    end

    it "counts bulk errors from the response" do
      filter = described_class.new(marketplace: "us")
      allow(filter).to(receive(:each_asin_hit).and_yield(hit("B0A")))
      allow(client).to(receive(:bulk).and_return(
        "errors" => true,
        "items" => [{ "index" => { "status" => 400, "error" => { "type" => "mapper_parsing_exception" } } }],
      ))

      stats = filter.bulk_index_asins!(client: client)
      expect(stats.bulk_errors).to(eq(1))
    end
  end
end
