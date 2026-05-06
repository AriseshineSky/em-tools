# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Em::Tools::LowestOfferInventoryAsinLoader do
  let(:client) { instance_double(Em::Clients::ElasticsearchClient) }

  before do
    allow(client).to receive(:index_exists?).with('em_inventory').and_return(true)
  end

  it 'collects ASIN-shaped source_product_id from hits' do
    allow(client).to receive(:iterate_query).and_yield(
      '_source' => { 'source' => 'amazon', 'source_product_id' => 'B00GOOD001' }
    ).and_yield(
      '_source' => { 'source' => 'amazon', 'source_product_id' => 'bad-id' }
    ).and_yield(
      '_source' => { 'source' => 'amazon', 'source_product_id' => 'B00GOOD001' }
    )

    loader = described_class.new(
      es_client: client,
      index: 'em_inventory',
      source_field: 'source.keyword',
      source_terms: %w[amazon],
      product_id_field: 'source_product_id',
      marketplace_field: nil,
      max_hits: nil
    )
    expect(loader.load('de')).to eq(['B00GOOD001'])
  end

  it 'returns empty when index missing' do
    allow(client).to receive(:index_exists?).with('missing').and_return(false)
    allow(client).to receive(:iterate_query)

    loader = described_class.new(
      es_client: client,
      index: 'missing',
      source_field: 'source.keyword',
      source_terms: %w[amazon],
      product_id_field: 'source_product_id',
      marketplace_field: nil,
      max_hits: nil
    )
    expect(loader.load('us')).to eq([])
    expect(client).not_to have_received(:iterate_query)
  end
end
