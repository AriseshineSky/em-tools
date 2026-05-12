# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe(EmTools::Core::Inventory::Sync) do
  describe "#sync_from_path inventory_feed resolution" do
    let(:sink) { instance_double(EmTools::Core::Sinks::ElasticsearchBulkSink, bulk: { "errors" => false }) }

    def write_csv(rows)
      f = Tempfile.new(["inv", ".csv"])
      f.write("ProductID,Source\n")
      rows.each { |id, source| f.write("#{id},#{source}\n") }
      f.flush
      f.path
    end

    it "writes the per-row Source as inventory_feed when feed_id is unset and rows agree" do
      captured = nil
      allow(sink).to(receive(:bulk)) do |body:|
        captured = body
        { "errors" => false }
      end
      sync = described_class.new(sink: sink, index: "em_inventory")

      sync.sync_from_path(write_csv([["a", "Ebay_US"], ["b", "Ebay_US"]]))

      feeds = captured.map { |op| op[:update][:data][:doc]["inventory_feed"] }
      expect(feeds).to(eq(["Ebay_US", "Ebay_US"]))
    end

    it "normalizes case-only Source mismatches to the first-seen casing" do
      captured = nil
      allow(sink).to(receive(:bulk)) do |body:|
        captured = body
        { "errors" => false }
      end
      sync = described_class.new(sink: sink, index: "em_inventory")

      sync.sync_from_path(write_csv([["a", "Ebay_US"], ["b", "EBAY_US"], ["c", "ebay_us"]]))

      feeds = captured.map { |op| op[:update][:data][:doc]["inventory_feed"] }
      expect(feeds).to(eq(["Ebay_US", "Ebay_US", "Ebay_US"]))
    end

    it "raises with a feed_id hint when Source values are truly different" do
      sync = described_class.new(sink: sink, index: "em_inventory")

      expect do
        sync.sync_from_path(write_csv([["a", "Ebay_US"], ["b", "Boyner"]]))
      end.to(raise_error(ArgumentError, /mixes Source values.*set feed_id/))
    end

    it "lets feed_id override the CSV Source column for every row" do
      captured = nil
      allow(sink).to(receive(:bulk)) do |body:|
        captured = body
        { "errors" => false }
      end
      sync = described_class.new(sink: sink, index: "em_inventory", feed_id: "Ebay_US")

      sync.sync_from_path(write_csv([["a", "Ebay_US"], ["b", "EBAY_US"], ["c", "Boyner"]]))

      feeds = captured.map { |op| op[:update][:data][:doc]["inventory_feed"] }
      expect(feeds).to(eq(["Ebay_US", "Ebay_US", "Ebay_US"]))
    end
  end

  describe "#sync_from_path with transforms" do
    let(:sink) { instance_double(EmTools::Core::Sinks::ElasticsearchBulkSink, bulk: { "errors" => false }) }

    it "strips fields listed in DropFields before bulk-indexing" do
      f = Tempfile.new(["inv", ".csv"])
      f.write("ProductID,Source,Handle,Variants\n")
      f.write("a,Ebay_US,my-handle,[1]\n")
      f.flush

      captured = nil
      allow(sink).to(receive(:bulk)) do |body:|
        captured = body
        { "errors" => false }
      end

      sync = described_class.new(
        sink: sink,
        index: "em_inventory",
        transforms: [EmTools::Core::Inventory::Transforms::DropFields.new("handle", "variants")],
      )
      sync.sync_from_path(f.path)

      doc = captured.first[:update][:data][:doc]
      expect(doc).not_to(have_key("handle"))
      expect(doc).not_to(have_key("variants"))
      expect(doc["product_id"]).to(eq("a"))
      expect(doc["inventory_feed"]).to(eq("Ebay_US"))
    end

    it "skips a row entirely when a transform returns nil" do
      f = Tempfile.new(["inv", ".csv"])
      f.write("ProductID,Source\nkeep,Ebay_US\nskip,Ebay_US\n")
      f.flush

      captured = []
      allow(sink).to(receive(:bulk)) do |body:|
        captured.concat(body)
        { "errors" => false }
      end

      drop_skip = ->(doc) { doc["product_id"] == "skip" ? nil : doc }
      sync = described_class.new(sink: sink, index: "em_inventory", transforms: [drop_skip])
      sync.sync_from_path(f.path)

      ids = captured.map { |op| op[:update][:_id] }
      expect(ids).to(eq(["keep"]))
    end
  end
end
