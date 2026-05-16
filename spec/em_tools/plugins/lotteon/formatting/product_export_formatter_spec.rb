# frozen_string_literal: true

require "spec_helper"
require "set"

RSpec.describe(EmTools::Plugins::Lotteon::Formatting::ProductExportFormatter) do
  let(:fixed_offer) do
    {
      "price" => 88.0,
      "quantity" => 40,
      "currency" => "USD",
      "src_price" => 9.0,
      "src_currency" => "USD",
    }
  end
  let(:calc) do
    instance_double(EmTools::Plugins::Amazon::Uploadable::Transforms::PriceCalculator, calc_offer: fixed_offer)
  end

  def base_doc(overrides = {})
    {
      "product_id" => "99",
      "title" => "Hello: 롯데ON world",
      "price" => 10.0,
      "currency" => "USD",
      "date" => "2024-09-06T10:35:27",
      "url" => "https://example.com/p",
      "images" => "https://example.com/a.jpg",
      "existence" => false,
      "description" => "<p><a href=\"x\">l</a>ink</p>",
      "shipping_fee" => 0.0,
      "variants" => nil,
      "options" => nil,
      "brand" => "B",
    }.merge(overrides)
  end

  subject(:formatter) { described_class.new(uploaded_product_ids: Set.new, price_calculator: calc, validate: false) }

  it "cleans title, sets lotteon sku/source, strips anchors twice, and applies price formatter" do
    out = formatter.call(base_doc)
    expect(out["source"]).to(eq("lotteon"))
    expect(out["sku"]).to(eq("X91_99"))
    expect(out["title"]).not_to(include("롯데ON"))
    expect(out["existence"]).to(be(true))
    expect(out["description"]).not_to(include("<a"))
    expect(out["price"]).to(eq(88.0))
    expect(out["quantity"]).to(eq(40))
    expect(out["cost_price"]).to(eq(9.0))
    expect(out["cost_currency"]).to(eq("USD"))
  end

  it "returns SKIP when variants are present" do
    expect(formatter.call(base_doc("variants" => [{ "sku" => "v" }]))).to(eq(described_class::SKIP))
  end

  it "returns SKIP when title is blank" do
    expect(formatter.call(base_doc("title" => "   "))).to(eq(described_class::SKIP))
  end

  it "drops invalid specification values" do
    out = formatter.call(base_doc(
      "specifications" => [{ "name" => "A", "value" => "無し" }, { "name" => "B", "value" => "ok" }],
    ))
    expect(out["specifications"].length).to(eq(1))
    expect(out["specifications"].first["value"]).to(eq("ok"))
  end
end
