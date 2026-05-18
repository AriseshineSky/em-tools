# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Inventory::SyncSources) do
  describe "gs_uri_template expansion" do
    def entries_for(node)
      described_class.new(preloaded_node: node).entries
    end

    it "expands AMZ_{marketplace}-Inv.csv into one source per marketplace" do
      sources = entries_for(
        "index" => "em_inventory",
        "cluster" => "primary",
        "sources" => [{
          "gs_uri_template" => "gs://em-bucket/AMZ_{marketplace}-Inv.csv",
          "marketplaces" => ["TR", "de"],
        }],
      )
      expect(sources.map(&:gs_uri)).to(eq([
        "gs://em-bucket/AMZ_TR-Inv.csv",
        "gs://em-bucket/AMZ_DE-Inv.csv",
      ]))
      expect(sources.map(&:index)).to(all(eq("em_inventory")))
      expect(sources.map(&:cluster)).to(all(eq("primary")))
    end

    it "expands marketplaces: all to the default Amazon inventory list" do
      sources = entries_for(
        "sources" => [{
          "gs_uri_template" => "gs://em-bucket/AMZ_{marketplace}-Inv.csv",
          "marketplaces" => "all",
        }],
      )
      expect(sources.size).to(eq(described_class::DEFAULT_AMAZON_INVENTORY_MARKETPLACES.size))
      expect(sources.first.gs_uri).to(eq("gs://em-bucket/AMZ_AE-Inv.csv"))
    end
  end
end
