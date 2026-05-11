# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::AmazonLowestOffer::Patterns::AsinPattern) do
  it "accepts B0-style ASINs" do
    expect(described_class.match?("B00TEST123")).to(be(true))
  end

  it "accepts 10-digit ISBN-style ids" do
    expect(described_class.match?("123456789X")).to(be(true))
  end

  it "rejects random strings" do
    expect(described_class.match?("not-an-asin")).to(be(false))
  end
end
