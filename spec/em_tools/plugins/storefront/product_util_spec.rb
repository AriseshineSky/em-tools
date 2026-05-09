# frozen_string_literal: true

require 'tmpdir'

class SpreeProductUtilSpecApi
  # rubocop:disable Metrics/MethodLength, Naming/AccessorMethodName -- fake API mirrors Spree client names.
  attr_reader :download_calls, :set_offers_calls

  def initialize
    @download_calls = []
    @set_offers_calls = []
  end

  def download_inventory(source, output_path)
    @download_calls << [source, output_path]
    File.write(
      output_path,
      [
        'ProductID,Source,SourceProductID,Handle,Variants,InStock',
        '1,AMZ_US,B001,handle-1,"[{""variant_id"":""v1""}]",true',
        ',AMZ_US,B002,handle-2,"[{""variant_id"":""v2""}]",true',
        '3,AMZ_US,B003,handle-3,invalid,true'
      ].join("\n"),
      mode: 'w'
    )
  end

  def get_multi_source_products(_source, page, _per_page)
    return { 'total_pages' => 2, 'products' => [{ 'id' => 1 }] } if page == 1

    { 'total_pages' => 2, 'products' => [{ 'id' => 2 }] }
  end

  def get_manual_products
    { 'products' => [{ 'id' => 10 }] }
  end

  def set_offers(offers)
    @set_offers_calls << offers
    { 'ok' => true }
  end
  # rubocop:enable Metrics/MethodLength, Naming/AccessorMethodName
end

RSpec.describe EmTools::Plugins::Storefront::ProductUtil do
  it 'downloads Amazon marketplace inventory into records and cleans up the temp file' do
    api = SpreeProductUtilSpecApi.new
    util = described_class.new('https://store.example.com', 'secret', spree_api: api)

    records = util.get_amz_products('us').to_a

    expect(records).to eq(
      [
        {
          'product_id' => '1',
          'source' => 'AMZ_US',
          'source_product_id' => 'B001',
          'handle' => 'handle-1',
          'variants' => [{ 'variant_id' => 'v1' }],
          'in_stock' => 'true'
        }
      ]
    )
    source, path = api.download_calls.first
    expect(source).to eq('AMZ_US')
    expect(File.exist?(path)).to be(false)
  end

  it 'loads products from a downloaded inventory file without requiring core fields' do
    api = SpreeProductUtilSpecApi.new
    util = described_class.new('https://store.example.com', 'secret', spree_api: api)

    Dir.mktmpdir do |dir|
      output_path = File.join(dir, 'inventory.csv')
      records = util.download_inventory('source-a', output_path).to_a

      expect(records.first).to include(
        'product_id' => '1',
        'source' => 'AMZ_US',
        'source_product_id' => 'B001',
        'variants' => [{ 'variant_id' => 'v1' }]
      )
      expect(records.length).to eq(2)
    end
  end

  it 'collects multi-source products across pages' do
    util = described_class.new('https://store.example.com', 'secret', spree_api: SpreeProductUtilSpecApi.new)

    expect(util.get_multi_sources_products('src')).to eq(
      1 => { 'id' => 1 },
      2 => { 'id' => 2 }
    )
  end

  it 'returns manual products from the API response' do
    util = described_class.new('https://store.example.com', 'secret', spree_api: SpreeProductUtilSpecApi.new)

    expect(util.get_manual_products).to eq([{ 'id' => 10 }])
  end

  it 'builds store offers and posts them to Spree' do
    api = SpreeProductUtilSpecApi.new
    util = described_class.new('https://store.example.com', 'secret', spree_api: api)

    offers = util.set_products_offer(
      'p1' => {
        'handle' => 'handle-1',
        'variants' => [{ 'variant_id' => 'v1' }],
        'offer' => {
          'price' => '12.345',
          'quantity' => '4.2',
          'currency' => 'USD',
          'src_price' => '8.999'
        }
      },
      'p2' => {
        'handle' => 'skip',
        'variants' => [],
        'offer' => false
      }
    )

    expect(offers).to eq(
      'p1' => {
        'handle' => 'handle-1',
        'product_id' => 'p1',
        'offers' => {
          'v1' => {
            'product_id' => 'p1',
            'variant_id' => 'v1',
            'price' => 12.35,
            'quantity' => 4.2,
            'currency' => 'USD',
            'cost_price' => 9.0,
            'cost_currency' => 'USD'
          }
        }
      }
    )
    expect(api.set_offers_calls.first).to eq(offers)
  end
end
