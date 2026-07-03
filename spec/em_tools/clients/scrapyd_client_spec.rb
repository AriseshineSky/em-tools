# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Clients::ScrapydClient) do
  let(:client) do
    described_class.new(
      url: "http://scrapyd.example:6800",
      project: "kr_products_spider",
      username: "user",
      password: "pass",
    )
  end

  it "posts schedule.json with spider settings" do
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPSuccess, body: '{"status":"ok","jobid":"abc"}')
    allow(response).to(receive(:is_a?).with(Net::HTTPSuccess).and_return(true))
    allow(Net::HTTP).to(receive(:start).and_yield(http))
    expect(http).to(receive(:open_timeout=).with(10))
    expect(http).to(receive(:read_timeout=).with(30))
    expect(http).to(receive(:request)) do |req|
      expect(req.path).to(eq("/schedule.json"))
      expect(req.body).to(include("project=kr_products_spider"))
      expect(req.body).to(include("spider=elevenst"))
      expect(req.body).to(include("urls=https%3A%2F%2Fwww.11st.co.kr%2Fproducts%2F1"))
      response
    end

    result = client.schedule_spider(
      spider: "elevenst",
      settings: { urls: "https://www.11st.co.kr/products/1", skip_existing: "0" },
    )
    expect(result["jobid"]).to(eq("abc"))
  end
end
