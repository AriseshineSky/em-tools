# frozen_string_literal: true

require "spec_helper"
require "set"

RSpec.describe(EmTools::Plugins::Lazada::Formatting::ProductExportFormatter) do
  let(:uploaded) { Set.new }
  let(:fixed_offer) do
    {
      "price" => 88.0,
      "quantity" => 10,
      "currency" => "USD",
      "src_price" => 9.0,
      "src_currency" => "USD",
    }
  end
  let(:calc) do
    instance_double(EmTools::Plugins::Amazon::Uploadable::Transforms::PriceCalculator, calc_offer: fixed_offer)
  end

  def base_product(overrides = {})
    {
      "product_id" => "L1",
      "price" => 15.0,
      "currency" => "USD",
      "date" => "2025-01-01T00:00:00",
      "url" => "https://example.com/p",
      "source" => "lazadacoth",
      "images" => "https://example.com/i.jpg",
      "existence" => true,
      "title" => "Serum",
      "description" => "<p>x</p>",
      "shipping_fee" => 0.0,
      "variants" => nil,
      "options" => nil,
    }.merge(overrides)
  end

  it "standardizes sku and source for Lazada TH" do
    formatter = described_class.new(uploaded_product_ids: uploaded, price_calculator: calc, validate: false)
    out = formatter.call(base_product("product_id" => "SKU-99"))
    expect(out["source"]).to(eq("Lazada TH"))
    expect(out["sku"]).to(eq("LZ-TH-SKU-99"))
    expect(out["price"]).to(eq(88.0))
  end

  it "build_for_profile applies marketplace sku prefix and display source" do
    profile = EmTools::Plugins::Lazada::MarketplaceProfile.fetch("my")
    formatter = described_class.build_for_profile(profile, validate: false)
    out = formatter.call(base_product("product_id" => "P1"))
    expect(out["source"]).to(eq("Lazada MY"))
    expect(out["sku"]).to(eq("LZ-MY-P1"))
  end

  it "returns SKIP for multi-variant rows like Oliveyoung" do
    formatter = described_class.new(uploaded_product_ids: uploaded, price_calculator: calc, validate: false)
    p = base_product("variants" => [{ "sku" => "a" }, { "sku" => "b" }])
    expect(formatter.call(p)).to(eq(described_class::SKIP))
  end
end
