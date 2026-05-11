# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Blacklist::Strategy::TitleBrand) do
  describe "#blocked? / #allow?" do
    let(:strategy) { described_class.new(["Bonafide", "Remedy's Nutrition", "Thrive Causemetics"]) }

    it "matches case-insensitively against the joined title+brand text" do
      hit = { "title" => "Some BONAFIDE Health gummy", "brand" => "Acme" }

      expect(strategy.blocked?(hit)).to(be(true))
      expect(strategy.allow?(hit)).to(be(false))
    end

    it "matches when only brand carries the blacklisted token" do
      expect(strategy.blocked?({ "title" => "Vitamin C", "brand" => "Bonafide" })).to(be(true))
    end

    it "joins title and brand with a single space (no concatenation across the boundary)" do
      expect(strategy.text_for({ "title" => "Foo", "brand" => "Bar" })).to(eq("foo bar"))
    end

    it "returns false for clean products" do
      hit = { "title" => "Plain candle", "brand" => "Acme" }

      expect(strategy.blocked?(hit)).to(be(false))
      expect(strategy.allow?(hit)).to(be(true))
    end

    it "returns false when title and brand are both missing/blank" do
      expect(strategy.blocked?({ "title" => "", "brand" => nil })).to(be(false))
      expect(strategy.blocked?({})).to(be(false))
    end
  end

  describe "#matched" do
    it "returns the deduped matched keywords" do
      strategy = described_class.new(["Bonafide", "Thrive", "remedy"])
      hit = { "title" => "Bonafide health remedy bonafide", "brand" => "Thrive" }

      expect(strategy.matched(hit)).to(contain_exactly("bonafide", "thrive", "remedy"))
    end

    it "returns [] for clean text" do
      strategy = described_class.new(["Bonafide"])

      expect(strategy.matched({ "title" => "fine", "brand" => "Acme" })).to(eq([]))
    end
  end

  describe "#blocked_record" do
    it "returns _id, title, brand, and matched keywords" do
      strategy = described_class.new(["Bonafide"])

      expect(strategy.blocked_record({ "title" => "Bonafide gummy", "brand" => "X" }, id: "doc-1"))
        .to(eq(
          "_id" => "doc-1",
          "title" => "Bonafide gummy",
          "brand" => "X",
          "matched" => ["bonafide"],
        ))
    end
  end

  describe "configuration" do
    it "honours custom title/brand field names" do
      strategy = described_class.new(["Bonafide"], title_field: "title_en", brand_field: "manufacturer")
      hit = { "title_en" => "Bonafide gummy", "manufacturer" => "X" }

      expect(strategy.blocked?(hit)).to(be(true))
    end

    it "is a no-op when the keyword list is empty" do
      strategy = described_class.new([])

      expect(strategy.keyword_count).to(eq(0))
      expect(strategy.blocked?({ "title" => "anything goes", "brand" => "Bonafide" })).to(be(false))
    end
  end
end
