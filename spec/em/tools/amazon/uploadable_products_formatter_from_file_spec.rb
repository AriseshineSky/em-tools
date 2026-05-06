# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'

RSpec.describe Em::Tools::Amazon::UploadableProductsFormatterFromFile do
  let(:tmpdir) { Dir.mktmpdir('em_tools_formatter') }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  let(:products_file) { File.join(tmpdir, 'asins.txt') }
  let(:output_file) { File.join(tmpdir, 'out.ndjson') }
  let(:emitter_dir) { File.join(tmpdir, 'emit') }

  let(:fake_client) do
    Class.new do
      attr_reader :product_mgets, :offer_mgets

      def initialize(product_index:, offer_index:, product_docs:, offer_docs:, offer_index_exists:)
        @product_index = product_index
        @offer_index = offer_index
        @product_docs = product_docs
        @offer_docs = offer_docs
        @offer_index_exists = offer_index_exists
        @product_mgets = []
        @offer_mgets = []
      end

      def index_exists?(name)
        return @offer_index_exists if name == @offer_index

        true
      end

      def mget(index:, ids:)
        if index == @product_index
          @product_mgets << ids.dup
          { 'docs' => ids.map { |id| @product_docs[id] || { 'found' => false, '_id' => id } } }
        elsif index == @offer_index
          @offer_mgets << ids.dup
          { 'docs' => ids.map { |id| @offer_docs[id] || { 'found' => false, '_id' => id } } }
        else
          raise "unexpected index: #{index}"
        end
      end
    end
  end

  # rubocop:disable Metrics/MethodLength -- default keyword map for formatter construction in examples.
  def build_formatter(**kwargs)
    defaults = {
      marketplace: 'us',
      products_path: products_file,
      output_path: output_file,
      source: 'SRC',
      source_code: 'SCODE',
      store_code: 'STORE1',
      emitter_dir: emitter_dir,
      product_index: 'prod_idx',
      offer_index: 'offer_idx',
      batch_size: 50
    }
    described_class.new(**defaults.merge(kwargs))
  end
  # rubocop:enable Metrics/MethodLength

  it 'merges offer price when offer doc is valid' do
    File.write(products_file, "B00GOOD1\n")

    pdoc = {
      'found' => true,
      '_id' => 'B00GOOD1',
      '_source' => {
        'asin' => 'B00GOOD1',
        'title' => 'Good Product',
        'price' => 99.0,
        'currency' => 'USD'
      }
    }
    odoc = {
      'found' => true,
      '_id' => 'B00GOOD1',
      '_source' => { 'price' => 12.34, 'currency' => 'USD' }
    }

    client = fake_client.new(
      product_index: 'prod_idx',
      offer_index: 'offer_idx',
      product_docs: { 'B00GOOD1' => pdoc },
      offer_docs: { 'B00GOOD1' => odoc },
      offer_index_exists: true
    )

    build_formatter.run!(client: client)

    lines = File.read(output_file).lines.map(&:strip).reject(&:empty?)
    expect(lines.size).to eq(1)
    row = JSON.parse(lines.first)
    expect(row['price']).to eq(12.34)
    expect(row['currency']).to eq('USD')
    expect(row['shipping_days_min']).to be_nil
    expect(row['shipping_days_max']).to be_nil
    expect(row['store_code']).to eq('STORE1')
  end

  it 'skips rows and records no_offer when offer index is missing' do
    File.write(products_file, "B00NONE1\n")

    pdoc = {
      'found' => true,
      '_id' => 'B00NONE1',
      '_source' => { 'asin' => 'B00NONE1', 'title' => 'T' }
    }

    client = fake_client.new(
      product_index: 'prod_idx',
      offer_index: 'offer_idx',
      product_docs: { 'B00NONE1' => pdoc },
      offer_docs: {},
      offer_index_exists: false
    )

    build_formatter.run!(client: client)

    expect(File.read(output_file).strip).to eq('')
    no_offer = File.read(File.join(emitter_dir, 'no_offer_asins.txt')).lines.map(&:strip)
    expect(no_offer).to include('B00NONE1')
  end

  it 'with skip_offers, takes price from product _source' do
    File.write(products_file, "B00SKIP1\n")

    pdoc = {
      'found' => true,
      '_id' => 'B00SKIP1',
      '_source' => {
        'asin' => 'B00SKIP1',
        'title' => 'Skip Offers',
        'price' => 55.5,
        'currency' => 'USD'
      }
    }

    client = fake_client.new(
      product_index: 'prod_idx',
      offer_index: 'offer_idx',
      product_docs: { 'B00SKIP1' => pdoc },
      offer_docs: {},
      offer_index_exists: true
    )

    build_formatter(skip_offers: true).run!(client: client)

    expect(client.offer_mgets).to be_empty

    row = JSON.parse(File.read(output_file).lines.first)
    expect(row['price']).to eq(55.5)
    expect(row['currency']).to eq('USD')
  end
end
