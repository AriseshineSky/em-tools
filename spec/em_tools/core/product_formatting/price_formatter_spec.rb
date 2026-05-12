# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::ProductFormatting::PriceFormatter) do
  # Stub price calculator: caller maps `src_offer["price"]` => recipe in `responses`.
  # `responses[price]` may be `false` (skip) or a Hash (offer).
  def price_calculator(responses)
    Class.new do
      def initialize(responses) = (@responses = responses)

      def calc_offer(src_offer)
        @responses.fetch(src_offer["price"])
      end
    end.new(responses)
  end

  it "copies the calculated offer onto the parent product (incl. cost_price + cost_currency)" do
    calc = price_calculator(
      10.0 => {
        "price" => 21.5,
        "quantity" => 50,
        "src_price" => 15.0,
        "currency" => "USD",
        "src_currency" => "KRW",
      },
    )
    product = { "price" => 10, "currency" => "KRW", "variants" => [] }

    described_class.new(price_calculator: calc).call(product)

    expect(product).to(include(
      "price" => 21.5,
      "quantity" => 50,
      "cost_price" => 15.0,
      "currency" => "USD",
      "cost_currency" => "KRW",
    ))
  end

  it "zeros out the parent and uses the source currency when the calculator returns false" do
    calc = price_calculator(0.0 => false)
    product = { "price" => 0, "currency" => "JPY", "variants" => nil }

    described_class.new(price_calculator: calc).call(product)

    expect(product).to(include("price" => 0, "quantity" => 0, "currency" => "JPY"))
    expect(product).not_to(include("cost_price"))
    expect(product).not_to(include("cost_currency"))
  end

  it "drops variants whose calculated quantity is non-positive but keeps the rest" do
    calc = price_calculator(
      5.0 => {
        "price" => 0,
        "quantity" => 0,
        "src_price" => 0,
        "currency" => "USD",
        "src_currency" => "USD",
      },
      8.0 => {
        "price" => 18.99,
        "quantity" => 25,
        "src_price" => 12.0,
        "currency" => "USD",
        "src_currency" => "USD",
      },
    )
    product = {
      "price" => 8,
      "currency" => "USD",
      "variants" => [
        { "sku" => "A", "price" => 5, "currency" => "USD" },
        { "sku" => "B", "price" => 8, "currency" => "USD" },
      ],
    }

    described_class.new(price_calculator: calc).call(product)

    expect(product["variants"].map { |v| v["sku"] }).to(eq(["B"]))
    expect(product["variants"].first).to(include("price" => 18.99, "quantity" => 25))
  end

  it "treats a zero-priced offer as a drop for variants (Python: `if offer and offer[\"price\"]`)" do
    # Reuse `0.0 =>` for both — variant with src price 0 receives the same zero offer
    # as the parent. Parent stays zeroed (kept), variant is dropped because its
    # quantity ends up 0.
    zero_offer = {
      "price" => 0,
      "quantity" => 0,
      "src_price" => 0,
      "currency" => "USD",
      "src_currency" => "USD",
    }
    calc = price_calculator(0.0 => zero_offer)
    product = { "price" => 0, "currency" => "USD", "variants" => [{ "sku" => "X", "price" => 0 }] }

    described_class.new(price_calculator: calc).call(product)

    expect(product["variants"]).to(eq([]))
    expect(product["price"]).to(eq(0))
  end

  it "handles missing variants key without raising" do
    calc = price_calculator(0.0 => false)
    product = { "price" => 0, "currency" => "USD" }

    expect { described_class.new(price_calculator: calc).call(product) }.not_to(raise_error)
    expect(product).not_to(have_key("variants"))
  end

  it "returns the same product object for chaining (mirrors Python in-place mutation)" do
    calc = price_calculator(0.0 => false)
    product = { "price" => 0, "currency" => "USD" }
    expect(described_class.new(price_calculator: calc).call(product)).to(equal(product))
  end
end
