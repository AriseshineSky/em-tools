# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Inventory::SyncRunner) do
  describe ".infer_source_name" do
    it "prefers feed_id when set" do
      name = described_class.infer_source_name(
        gs_uri: "gs://em-bucket/AMZ_DE-Inv.csv",
        feed_id: "PinnedFeed",
      )
      expect(name).to(eq("PinnedFeed"))
    end

    it "derives AMZ marketplace codes from inventory CSV filenames" do
      name = described_class.infer_source_name(
        gs_uri: "gs://em-bucket/AMZ_DE-Inv.csv",
        feed_id: nil,
      )
      expect(name).to(eq("AMZ_DE"))
    end

    it "strips -Inv.csv from other inventory filenames" do
      name = described_class.infer_source_name(
        gs_uri: "gs://em-bucket/Ebay_US-Inv.csv",
        feed_id: "",
      )
      expect(name).to(eq("Ebay_US"))
    end
  end
end
