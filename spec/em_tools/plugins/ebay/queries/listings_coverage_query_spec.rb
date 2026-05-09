# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EmTools::Plugins::Ebay::Queries::ListingsCoverageQuery do
  let(:es_client) { instance_double(EmTools::Clients::ElasticsearchClient) }
  let(:snapshot_time) { Time.utc(2026, 1, 15, 12, 0, 0) }

  # rubocop:disable Metrics/MethodLength -- ES activity aggregation fixture
  def activity_response(total:, last24: 1, missing_time: 0)
    {
      'hits' => { 'total' => { 'value' => total } },
      'aggregations' => {
        'missing_time' => { 'doc_count' => missing_time },
        'with_time' => {
          'windows' => {
            'buckets' => {
              'last_24h' => { 'doc_count' => last24 },
              'hours_24_to_48_ago' => { 'doc_count' => 0 },
              'hours_48_to_72h_ago' => { 'doc_count' => 0 },
              'older_than_72h' => { 'doc_count' => 0 },
              'at_or_after_now' => { 'doc_count' => 0 },
              'other_time_window' => { 'doc_count' => 0 }
            }
          }
        }
      }
    }
  end
  # rubocop:enable Metrics/MethodLength

  def coverage_response(keys)
    {
      'aggregations' => {
        'seed_ids_present' => {
          'buckets' => keys.map { |k| { 'key' => k, 'doc_count' => 1 } }
        }
      }
    }
  end

  it 'aggregates time windows and coverage for seed ids against a configurable index' do
    seed_path = File.join('/tmp', "ebay_cov_seed_#{Process.pid}.txt")
    File.write(
      seed_path,
      "x\t{\"source_product_id\":\"396083694860\"}\n",
      encoding: 'UTF-8'
    )

    allow(es_client).to receive(:search).and_return(
      activity_response(total: 2, last24: 1, missing_time: 0),
      coverage_response(['396083694860'])
    )

    q = described_class.new(
      es_client: es_client,
      marketplace: 'us',
      snapshot_time: snapshot_time,
      index_name: 'ebay_test_products',
      id_field: 'product_id.keyword',
      time_field: 'time',
      seed_file: seed_path
    )
    row = q.fetch_row

    expect(row[:index_name]).to eq('ebay_test_products')
    expect(row[:seed_ids_loaded]).to eq(1)
    expect(row[:time_last_24h]).to eq(1)
    expect(row[:seed_listing_docs_total]).to eq(2)
    expect(row[:seed_ids_found_in_index]).to eq(1)
    expect(row[:seed_ids_missing_from_index]).to eq(0)
  ensure
    File.unlink(seed_path) if seed_path && File.file?(seed_path)
  end
end
