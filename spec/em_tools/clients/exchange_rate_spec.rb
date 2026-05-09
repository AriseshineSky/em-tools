# frozen_string_literal: true

require 'json'
require 'spec_helper'

RSpec.describe EmTools::Clients::ExchangeRate do
  before { described_class.reset_cache! }
  after  { described_class.reset_cache! }

  it 'returns 1 when base and target are the same' do
    expect(described_class.get_exchange_rate('USD', 'USD')).to eq(1)
  end

  it 'uses the injected http_client when available, then memoizes' do
    fake_http = FakeHttpClient.new(body: { 'data' => { 'mid' => 1234.5 } }.to_json)
    rate = described_class.get_exchange_rate('USD', 'KRW', http_client: fake_http)
    expect(rate).to eq(1234.5)
    expect(fake_http.calls).to eq(1)

    # second call hits the cache; provider must not be invoked again
    rate2 = described_class.get_exchange_rate('USD', 'KRW', http_client: fake_http)
    expect(rate2).to eq(1234.5)
    expect(fake_http.calls).to eq(1)
  end

  it 'falls back to the bundled default rates when HTTP fails' do
    failing_http = FakeHttpClient.new(body: 'no', code: '500')
    rate = described_class.get_exchange_rate('USD', 'KRW', http_client: failing_http)
    expect(rate).to eq(described_class::DEFAULT_RATES['KRW'])
  end

  it 'inverts default USD-keyed rates when target is USD and base has a default entry' do
    failing_http = FakeHttpClient.new(body: 'no', code: '500')
    rate = described_class.get_exchange_rate('GBP', 'USD', http_client: failing_http)
    expected = 1.0 / described_class::DEFAULT_RATES['GBP']
    expect(rate).to be_within(1e-9).of(expected)
  end
end

# Minimal Net::HTTP-compatible double for exchange_rate specs.
class FakeHttpClient
  attr_reader :calls

  def initialize(body:, code: '200')
    @body = body
    @code = code
    @calls = 0
  end

  def get_response(_uri)
    @calls += 1
    Struct.new(:code, :body).new(@code, @body)
  end
end
