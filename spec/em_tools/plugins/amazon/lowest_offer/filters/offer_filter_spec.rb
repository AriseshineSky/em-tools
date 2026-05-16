# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Amazon::LowestOffer::Filters::OfferFilter) do
  def offer(**attrs)
    {
      "price" => 0.0,
      "product_price" => 0.0,
      "shipping_price" => 0.0,
      "currency" => "USD",
      "fba" => false,
      "condition" => "new",
      "subcondition" => "new",
    }.merge(attrs.transform_keys(&:to_s))
  end

  describe "#filter_all" do
    it "keeps fba offers when fba is required" do
      filter = described_class.new(fba: true)
      kept = filter.filter_all([offer(fba: true, price: 5), offer(fba: false, price: 3)])
      expect(kept.size).to(eq(1))
      expect(kept.first["fba"]).to(be(true))
    end

    it "rejects fba offers below the configured min price floor" do
      filter = described_class.new(fba: true, price: 10)
      kept = filter.filter_all([offer(fba: true, price: 5), offer(fba: true, price: 20)])
      expect(kept.map { |o| o["price"] }).to(eq([20]))
    end

    it "enforces shipping_time max minutes and availability_type=now" do
      filter = described_class.new(shipping_time: 5)
      offers = [
        offer(shipping_time: { "availability_type" => "NOW", "min" => 3 }, price: 1),
        offer(shipping_time: { "availability_type" => "NOW", "min" => 9 }, price: 2),
        offer(shipping_time: { "availability_type" => "LATER", "min" => 2 }, price: 3),
      ]
      expect(filter.filter_all(offers).map { |o| o["price"] }).to(eq([1]))
    end

    it "requires rating/feedback only for non-fba offers without buybox" do
      filter = described_class.new(rating: 90, feedback: 100)
      offers = [
        offer(price: 1, fba: false, rating: 80, feedback: 200),       # rating too low
        offer(price: 2, fba: false, rating: 95, feedback: 50),        # feedback too low
        offer(price: 3, fba: false, rating: 95, feedback: 150),       # passes
        offer(price: 4, fba: true, rating: 0, feedback: 0), # fba bypass
      ]
      expect(filter.filter_all(offers).map { |o| o["price"] }).to(contain_exactly(3, 4))
    end

    it "enforces subcondition with ge strategy by default" do
      filter = described_class.new(subcondition: 80)
      offers = [
        offer(price: 1, subcondition: "good"),       # 70 < 80 -> reject
        offer(price: 2, subcondition: "very_good"),  # 81 >= 80 -> keep
        offer(price: 3, subcondition: "mint"), # 90 >= 80 -> keep
      ]
      expect(filter.filter_all(offers).map { |o| o["price"] }).to(contain_exactly(2, 3))
    end

    it "supports eq subcondition strategy" do
      filter = described_class.new(subcondition: 90, strategies: { subcondition_strategy: "eq" })
      offers = [
        offer(price: 1, subcondition: "mint"), # 90 == 90 -> keep
        offer(price: 2, subcondition: "very_good"), # 81 != 90 -> reject
      ]
      expect(filter.filter_all(offers).map { |o| o["price"] }).to(eq([1]))
    end
  end

  describe "#filter (provider_type)" do
    let(:offers) do
      [
        offer(price: 5, fba: false),
        offer(price: 1, fba: false),
        offer(price: 8, fba: true),
        offer(price: 3, fba: false),
      ]
    end

    it "picks the lowest priced when provider_type='min'" do
      filter = described_class.new(provider_type: "min", picked_count: 4)
      picked = filter.filter(offers)
      expect(picked["price"]).to(eq(1))
    end

    it "picks the max within picked window when provider_type='max'" do
      filter = described_class.new(provider_type: "max", picked_count: 2)
      picked = filter.filter(offers)
      expect(picked["price"]).to(eq(3))
    end

    it "prefers the first FBA offer in picked window when provider_type='fba'" do
      filter = described_class.new(provider_type: "fba", picked_count: 4)
      picked = filter.filter(offers)
      expect(picked["fba"]).to(be(true))
      expect(picked["offers"]).to(eq(4))
    end

    it "returns nil when fewer offers than the offers threshold" do
      filter = described_class.new(provider_type: "min", offers: 5)
      expect(filter.filter(offers)).to(be_nil)
    end

    it "averages product/shipping/price when provider_type=avg" do
      avg_offers = [
        offer(price: 2, product_price: 1, shipping_price: 1),
        offer(price: 4, product_price: 3, shipping_price: 1),
      ]
      filter = described_class.new(provider_type: "avg", picked_count: 2)
      picked = filter.filter(avg_offers)
      expect(picked["price"]).to(eq(3.0))
      expect(picked["product_price"]).to(eq(2.0))
      expect(picked["offers"]).to(eq(2))
    end
  end
end
