# frozen_string_literal: true

require "spec_helper"
require "set"

RSpec.describe(EmTools::Plugins::Oliveyoung::Formatting::ProductExportFormatter) do
  let(:uploaded) { Set.new }
  let(:fixed_offer) do
    {
      "price" => 99.99,
      "quantity" => 50,
      "currency" => "USD",
      "src_price" => 10.0,
      "src_currency" => "USD",
    }
  end
  let(:calc) do
    instance_double(EmTools::Plugins::Amazon::Uploadable::Transforms::PriceCalculator, calc_offer: fixed_offer)
  end
  let(:logger) { instance_double(Logger, warn: nil) }

  def base_product(overrides = {})
    {
      "product_id" => "P1",
      "price" => 20.0,
      "currency" => "USD",
      "date" => "2024-09-06T10:35:27",
      "url" => "https://example.com/p",
      "source" => "oliveyoung",
      "images" => "https://example.com/a.jpg",
      "existence" => true,
      "title" => "T",
      "description" => "<p>Hello</p>",
      "shipping_fee" => 0.0,
      "variants" => nil,
      "options" => nil,
    }.merge(overrides)
  end

  describe "filtering" do
    subject(:formatter) { described_class.new(uploaded_product_ids: uploaded, price_calculator: calc, validate: false) }

    it "returns SKIP when more than one variant" do
      p = base_product("variants" => [{ "sku" => "a", "price" => 1 }, { "sku" => "b", "price" => 2 }])
      expect(formatter.call(p)).to(eq(described_class::SKIP))
    end

    it "returns SKIP when options are non-empty" do
      p = base_product("options" => [{ "name" => "Size", "id" => "1" }])
      expect(formatter.call(p)).to(eq(described_class::SKIP))
    end

    it "returns SKIP when product_id is already uploaded" do
      p = base_product("product_id" => "UP-1")
      fmt = described_class.new(
        uploaded_product_ids: Set.new(["UP-1"]),
        price_calculator: calc,
        validate: false,
      )
      expect(fmt.call(p)).to(eq(described_class::SKIP))
    end
  end

  describe "standardize + price" do
    subject(:formatter) { described_class.new(uploaded_product_ids: uploaded, price_calculator: calc, validate: false) }

    it "sets Oliveyoung sku, source, shipping days, and runs price formatter" do
      out = formatter.call(base_product("product_id" => "99"))
      expect(out["source"]).to(eq("Oliveyoung"))
      expect(out["sku"]).to(eq("X92-99"))
      expect(out["shipping_days_min"]).to(be_nil)
      expect(out["shipping_days_max"]).to(be_nil)
      expect(out["price"]).to(eq(99.99))
      expect(out["quantity"]).to(eq(50))
    end

    it "fills description from specifications when description is blank" do
      p = base_product(
        "description" => "",
        "specifications" => [{ "name" => "Color", "value" => "Red" }],
      )
      out = formatter.call(p)
      expect(out["description"]).to(eq("<ul><li>Color: Red</li></ul>"))
    end
  end

  describe "StandardProduct validation" do
    it "returns SKIP and logs when validation fails" do
      allow(logger).to(receive(:warn))
      fmt = described_class.new(
        uploaded_product_ids: uploaded,
        price_calculator: calc,
        logger: logger,
        validate: true,
      )
      bad = base_product("url" => "not-a-url")
      expect(fmt.call(bad)).to(eq(described_class::SKIP))
      expect(logger).to(have_received(:warn))
    end

    it "returns priced hash when the payload is valid" do
      fmt = described_class.new(uploaded_product_ids: uploaded, price_calculator: calc, validate: true)
      out = fmt.call(base_product)
      expect(out).to(be_a(Hash))
      expect(out["price"]).to(eq(99.99))
    end
  end
end
