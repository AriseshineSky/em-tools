# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Blacklist::Engine::AhoCorasick) do
  describe "#blocked?" do
    it "matches case-insensitively by default" do
      engine = described_class.new(["badword"])

      expect(engine.blocked?("contains BADWORD in title")).to(be(true))
      expect(engine.blocked?("clean product title")).to(be(false))
    end

    it "honours case_sensitive: true" do
      engine = described_class.new(["BadWord"], case_sensitive: true)

      expect(engine.blocked?("BadWord here")).to(be(true))
      expect(engine.blocked?("badword here")).to(be(false))
    end

    it "is a no-op when the keyword set is empty" do
      engine = described_class.new([])

      expect(engine.keyword_count).to(eq(0))
      expect(engine.blocked?("anything goes")).to(be(false))
      expect(engine.lookup("anything goes")).to(eq([]))
    end

    it "normalises keywords (downcase, strip, dedupe, drop blanks)" do
      engine = described_class.new(["foo", "FOO", " foo ", "", nil])

      expect(engine.keyword_count).to(eq(1))
    end

    it "treats ® as a separator when matching product text" do
      engine = described_class.new(["biting"])

      expect(engine.blocked?("ARK® Biting and Chewing")).to(be(true))
    end
  end

  describe "#lookup" do
    it "returns the unique matched keywords" do
      engine = described_class.new(["bonafide", "thrive", "remedy"])

      expect(engine.lookup("Bonafide health remedy bonafide thrive"))
        .to(contain_exactly("bonafide", "thrive", "remedy"))
    end
  end
end
