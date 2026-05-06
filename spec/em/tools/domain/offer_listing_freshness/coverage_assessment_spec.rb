# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Em::Tools::Domain::OfferListingFreshness::CoverageAssessment do
  let(:client) { instance_double(Em::Clients::ElasticsearchClient) }
  let(:captured_at) { Time.utc(2026, 5, 6, 12, 0, 0) }

  it 'delegates to LowestOfferListingsCoverageQuery with id_source seed' do
    query = instance_double(Em::Tools::LowestOfferListingsCoverageQuery, fetch_all: [{ marketplace: 'DE' }])
    expect(Em::Tools::LowestOfferListingsCoverageQuery).to receive(:new).with(
      hash_including(es_client: client, id_source: 'seed', snapshot_time: captured_at, marketplaces: %w[de])
    ).and_return(query)

    rows = described_class.new(
      search_client: client,
      watched_product_id_source: Em::Tools::Domain::OfferListingFreshness::WatchedProductIdSource::FROM_PROMOTION_SEED_FEED,
      marketplaces: %w[de]
    ).snapshot_rows_for_all_configured_marketplaces(snapshot_captured_at: captured_at)

    expect(rows).to eq([{ marketplace: 'DE' }])
  end

  it 'maps operating inventory to id_source inventory' do
    query = instance_double(Em::Tools::LowestOfferListingsCoverageQuery, fetch_marketplace: { marketplace: 'US' })
    expect(Em::Tools::LowestOfferListingsCoverageQuery).to receive(:new).with(
      hash_including(es_client: client, id_source: 'inventory')
    ).and_return(query)

    row = described_class.new(
      search_client: client,
      watched_product_id_source: Em::Tools::Domain::OfferListingFreshness::WatchedProductIdSource::FROM_OPERATING_INVENTORY
    ).snapshot_rows_for_marketplace('us', snapshot_captured_at: captured_at)

    expect(row).to eq({ marketplace: 'US' })
  end
end
