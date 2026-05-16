# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Lazada::MarketplaceProfile) do
  describe ".fetch" do
    it "merges TH defaults" do
      p = described_class.fetch("th")
      expect(p.exporter_key).to(eq("lazada_th_products"))
      expect(p.display_source).to(eq("Lazada TH"))
      expect(p.sku_prefix).to(eq("LZ-TH-"))
      expect(p.inventory_source).to(eq("lazadacoth"))
    end

    it "merges MY defaults with different price template" do
      p = described_class.fetch("my")
      expect(p.exporter_key).to(eq("lazada_my_products"))
      expect(p.display_source).to(eq("Lazada MY"))
      expect(p.sku_prefix).to(eq("LZ-MY-"))
      expect(p.price_rules_hash["roi"]).to(eq(0.28))
    end

    it "deep-merges YAML overrides from settings" do
      allow(EmTools::Core::Config).to(receive(:settings).and_return({
        "lazada_marketplaces" => {
          "th" => {
            "sku_prefix" => "X-",
            "price_rules" => { "roi" => 0.4 },
            "formatter_filters" => { "skip_options" => false },
          },
        },
      }))
      p = described_class.fetch("th")
      expect(p.sku_prefix).to(eq("X-"))
      expect(p.price_rules_hash["roi"]).to(eq(0.4))
      expect(p.price_rules_hash["ad_cost"]).to(eq(4.5))
      expect(p.skip_options?).to(be(false))
      expect(p.skip_multi_variant?).to(be(true))
    end
  end
end
