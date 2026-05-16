# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Translation::TitleScriptFilter) do
  describe ".allow?" do
    it "returns false for blank text" do
      expect(described_class.allow?("", ["ko", "ja"])).to(be(false))
      expect(described_class.allow?("   ", ["ko", "ja"])).to(be(false))
    end

    it "returns false when no language codes are given" do
      expect(described_class.allow?("한글", [])).to(be(false))
    end

    it "matches Korean when Hangul is present" do
      expect(described_class.allow?("스킨케어 세트", ["ko", "ja"])).to(be(true))
    end

    it "matches Japanese when kana is present" do
      expect(described_class.allow?("化粧水 セット", ["ko", "ja"])).to(be(true))
    end

    it "matches Japanese for CJK without Hangul (Chinese-like script)" do
      expect(described_class.allow?("美容液", ["ko", "ja"])).to(be(true))
    end

    it "does not treat pure Hangul as Japanese-only via CJK branch" do
      expect(described_class.allow?("한글만", ["ja"])).to(be(false))
    end

    it "returns false for ASCII-only titles" do
      expect(described_class.allow?("Vitamin C Serum", ["ko", "ja"])).to(be(false))
    end
  end
end
