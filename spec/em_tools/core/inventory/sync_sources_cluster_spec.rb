# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Inventory::SyncSources) do
  describe "cluster parsing" do
    def entries_for(node)
      described_class.new(preloaded_node: node).entries
    end

    it "defaults to nil when neither section default nor per-source cluster is set" do
      sources = entries_for("sources" => ["gs://b/x.csv"])
      expect(sources.map(&:cluster)).to(eq([nil]))
    end

    it "applies the section default to bare-string sources" do
      sources = entries_for(
        "cluster" => "primary",
        "sources" => ["gs://b/x.csv", "gs://b/y.csv"],
      )
      expect(sources.map(&:cluster)).to(eq(["primary", "primary"]))
    end

    it "lets per-source cluster: override the section default" do
      sources = entries_for(
        "cluster" => "primary",
        "sources" => [
          "gs://b/x.csv",
          { "uri" => "gs://b/y.csv", "cluster" => "data" },
        ],
      )
      expect(sources.map(&:cluster)).to(eq(["primary", "data"]))
    end

    it "treats an explicit blank cluster: as 'inherit the section default' (no surprise empty strings)" do
      sources = entries_for(
        "cluster" => "primary",
        "sources" => [{ "uri" => "gs://b/x.csv", "cluster" => "  " }],
      )
      expect(sources.first.cluster).to(eq("primary"))
    end

    it "preserves non-cluster fields when cluster: is set" do
      sources = entries_for(
        "sources" => [{
          "uri" => "gs://b/x.csv",
          "index" => "ebay_us_products",
          "feed_id" => "ebay",
          "cluster" => "data",
        }],
      )
      src = sources.first
      expect(src.gs_uri).to(eq("gs://b/x.csv"))
      expect(src.index).to(eq("ebay_us_products"))
      expect(src.feed_id).to(eq("ebay"))
      expect(src.cluster).to(eq("data"))
    end
  end
end
