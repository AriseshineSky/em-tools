# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::AmazonUploadable::Transforms::PriceCalculator) do
  let(:rate_table) do
    { ["USD", "USD"] => 1, ["USD", "KRW"] => 1300.0, ["USD", "CNY"] => 7.0 }
  end
  let(:rate_provider) { ->(base, target) { rate_table.fetch([base.to_s.upcase, target.to_s.upcase]) } }

  describe "#initialize" do
    it "merges price_rules over defaults and resolves the target FX rate up front" do
      calc = described_class.new(
        target_currency: "KRW",
        exchange_rate_provider: rate_provider,
        price_rules: { "margin" => 0.6, "tax_rate" => 0.1 },
      )
      expect(calc.exchange_rate).to(eq(1300.0))
      expect(calc.target_currency).to(eq("KRW"))
      expect(calc.rules["margin"]).to(eq(0.6))
      expect(calc.rules["tax_rate"]).to(eq(0.1))
      expect(calc.rules["ad_cost"]).to(eq(3)) # default preserved
    end

    it "accepts a precomputed exchange_rate without calling the provider" do
      provider = ->(*_) { raise "should not be called" }
      calc = described_class.new(
        target_currency: "KRW",
        exchange_rate: 1500.0,
        exchange_rate_provider: provider,
      )
      expect(calc.exchange_rate).to(eq(1500.0))
    end
  end

  describe "#calc_offer" do
    let(:calc) do
      described_class.new(
        target_currency: "KRW",
        exchange_rate_provider: rate_provider,
        min_profit_amount: 5,
        default_qty: 50,
      )
    end

    it "returns false when src_offer is false" do
      expect(calc.calc_offer(false)).to(be(false))
    end

    it "returns a zero offer in target currency when price is missing or zero" do
      expect(calc.calc_offer(nil)).to(eq(
        "price" => 0,
        "quantity" => 0,
        "currency" => "KRW",
        "src_price" => 0,
        "src_currency" => "KRW",
      ))
      expect(calc.calc_offer({ "price" => 0, "currency" => "USD" })).to(eq(
        "price" => 0,
        "quantity" => 0,
        "currency" => "KRW",
        "src_price" => 0,
        "src_currency" => "KRW",
      ))
    end

    it "computes target-currency price using max(amount-floor, margin) clamped by product cost" do
      offer = calc.calc_offer({ "price" => 10, "currency" => "USD" })
      expect(offer["currency"]).to(eq("KRW"))
      expect(offer["quantity"]).to(eq(50))
      expect(offer["price"]).to(be > 10 * 1300) # at least source converted to KRW
      expect(offer["src_price"]).to(eq(10 * 1300.0))
    end

    it "converts non-USD source via the provider before pricing" do
      offer = calc.calc_offer({ "price" => 70, "currency" => "CNY" })
      # 70 CNY = 10 USD given USD->CNY=7, then -> KRW at 1300
      expect(offer["src_price"]).to(eq(13_000.0))
    end

    it "forces quantity to 0 when availability is non-now and not FBA" do
      offer = calc.calc_offer({
        "price" => 10,
        "currency" => "USD",
        "fba" => false,
        "shipping_time" => { "availability_type" => "LATER" },
      })
      expect(offer["quantity"]).to(eq(0))
    end
  end

  describe "#calc_cost_usd / #calc_cost" do
    let(:calc) do
      described_class.new(target_currency: "KRW", exchange_rate_provider: rate_provider)
    end

    it "returns 0 for falsy or zero-priced source" do
      expect(calc.calc_cost_usd(nil)).to(eq(0))
      expect(calc.calc_cost_usd(false)).to(eq(0))
      expect(calc.calc_cost_usd({ "price" => 0 })).to(eq(0))
    end

    it "rounds USD cost with tax_rate applied" do
      # default tax_rate=0.09 -> 10 * 1.09 = 10.9
      expect(calc.calc_cost_usd({ "price" => 10, "currency" => "USD" })).to(eq(10.9))
    end

    it "multiplies by exchange_rate to get target-currency cost" do
      # 10.9 USD * 1300 KRW/USD = 14170
      expect(calc.calc_cost({ "price" => 10, "currency" => "USD" })).to(eq(14_170.0))
    end
  end
end
