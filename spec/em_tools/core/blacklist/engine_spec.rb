# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Blacklist::Engine) do
  let(:keywords) { ["badword"] }
  let(:engine) { described_class.new(keywords) }

  let(:blocked_cases) do
    [
      "contains badword in title",
    ]
  end

  let(:clean_cases) do
    [
      "clean product title",
    ]
  end

  describe "#blocked?" do
    context "when text contains blacklist keywords" do
      it "returns true for all blocked cases" do
        blocked_cases.each do |text|
          expect(engine.blocked?(text)).to(be(true))
        end
      end
    end

    context "when text is clean" do
      it "returns false for all clean cases" do
        clean_cases.each do |text|
          expect(engine.blocked?(text)).to(be(false))
        end
      end
    end
  end
end
