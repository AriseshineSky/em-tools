# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Inventory::SyncSources) do
  describe "format detection" do
    def entries_for(node)
      described_class.new(preloaded_node: node).entries
    end

    it "uses asin_list for .txt sources" do
      src = entries_for("sources" => ["gs://em-bucket/em-analytics/sources/AMZ_DE.txt"]).first
      expect(src.format).to(eq(:asin_list))
    end

    it "uses csv for .csv sources" do
      src = entries_for("sources" => ["gs://em-bucket/AMZ_DE-Inv.csv"]).first
      expect(src.format).to(eq(:csv))
    end

    it "honours explicit format and source keys" do
      src = entries_for(
        "sources" => [{
          "uri" => "gs://em-bucket/em-analytics/sources/AMZ_DE.txt",
          "format" => "asin_list",
          "source" => "AMZ_DE",
        }],
      ).first
      expect(src.format).to(eq(:asin_list))
      expect(src.feed_id).to(eq("AMZ_DE"))
    end
  end
end
