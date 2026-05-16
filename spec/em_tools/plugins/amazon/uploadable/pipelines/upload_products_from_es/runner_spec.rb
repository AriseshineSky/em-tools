# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Amazon::Uploadable::Pipelines::UploadProductsFromEs::Runner) do
  let(:logger) { instance_double(Logger, info: nil, error: nil) }

  it "builds describe including price rules and capability flags" do
    cfg = { "price" => { "rules" => { "amz_de" => { "roi" => 0.4 } } } }
    runner = described_class.new(marketplace: "de", ttl: 14, config: cfg, logger: logger)
    d = runner.describe
    expect(d[:asin_index]).to(eq("amz_asins_de"))
    expect(d[:ttl]).to(eq(14))
    expect(d[:price_rules][:roi]).to(eq(0.4))
    expect(d[:implemented][:asin_elasticsearch_stream]).to(be(true))
    expect(d[:implemented][:product_service]).to(be(false))
  end

  it "uses default ASIN index name from marketplace" do
    runner = described_class.new(marketplace: "de", logger: logger)
    expect(runner.describe[:asin_index]).to(eq("amz_asins_de"))
  end
end
