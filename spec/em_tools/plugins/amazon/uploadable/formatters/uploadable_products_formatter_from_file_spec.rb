# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"

RSpec.describe(EmTools::Plugins::Amazon::Uploadable::Formatters::UploadableProductsFormatterFromFile) do
  let(:tmpdir) { Dir.mktmpdir("em_tools_formatter") }
  let(:products_file) { File.join(tmpdir, "asins.txt") }
  let(:output_file) { File.join(tmpdir, "out.ndjson") }
  let(:emitter_dir) { File.join(tmpdir, "emit") }
  let(:fake_client) do
    Class.new do
      attr_reader :product_mgets, :offer_mgets, :bulk_bodies, :refreshed

      def initialize(product_index:, offer_index:, product_docs:, offer_docs:, offer_index_exists:)
        @product_index = product_index
        @offer_index = offer_index
        @product_docs = product_docs
        @offer_docs = offer_docs
        @offer_index_exists = offer_index_exists
        @product_mgets = []
        @offer_mgets = []
        @bulk_bodies = []
        @refreshed = []
      end

      def index_exists?(name)
        return @offer_index_exists if name == @offer_index

        true
      end

      def mget(index:, ids:)
        if index == @product_index
          @product_mgets << ids.dup
          { "docs" => ids.map { |id| @product_docs[id] || { "found" => false, "_id" => id } } }
        elsif index == @offer_index
          @offer_mgets << ids.dup
          { "docs" => ids.map { |id| @offer_docs[id] || { "found" => false, "_id" => id } } }
        else
          raise "unexpected index: #{index}"
        end
      end

      def bulk(body:)
        @bulk_bodies << body
        items = body.split("\n").reject(&:empty?).count / 2
        { "errors" => false, "items" => Array.new(items) { { "index" => { "status" => 201 } } } }
      end

      def refresh(index)
        @refreshed << index
        { "acknowledged" => true }
      end
    end
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  # -- default keyword map for formatter construction in examples.
  def build_formatter(**kwargs)
    defaults = {
      marketplace: "us",
      products_path: products_file,
      output_path: output_file,
      source: "SRC",
      source_code: "SCODE",
      store_code: "STORE1",
      emitter_dir: emitter_dir,
      product_index: "prod_idx",
      offer_index: "offer_idx",
      batch_size: 50,
    }
    described_class.new(**defaults.merge(kwargs))
  end
  # rubocop:enable Metrics/MethodLength

  it "merges offer price when offer doc is valid" do
    File.write(products_file, "B00GOOD1\n")

    pdoc = {
      "found" => true,
      "_id" => "B00GOOD1",
      "_source" => {
        "asin" => "B00GOOD1",
        "title" => "Good Product",
        "price" => 99.0,
        "currency" => "USD",
      },
    }
    odoc = {
      "found" => true,
      "_id" => "B00GOOD1",
      "_source" => { "price" => 12.34, "currency" => "USD" },
    }

    client = fake_client.new(
      product_index: "prod_idx",
      offer_index: "offer_idx",
      product_docs: { "B00GOOD1" => pdoc },
      offer_docs: { "B00GOOD1" => odoc },
      offer_index_exists: true,
    )

    build_formatter.run!(client: client)

    lines = File.read(output_file).lines.map(&:strip).reject(&:empty?)
    expect(lines.size).to(eq(1))
    row = JSON.parse(lines.first)
    expect(row["price"]).to(eq(12.34))
    expect(row["currency"]).to(eq("USD"))
    expect(row["shipping_days_min"]).to(be_nil)
    expect(row["shipping_days_max"]).to(be_nil)
    expect(row["store_code"]).to(eq("STORE1"))
  end

  it "skips rows and records no_offer when offer index is missing" do
    File.write(products_file, "B00NONE1\n")

    pdoc = {
      "found" => true,
      "_id" => "B00NONE1",
      "_source" => { "asin" => "B00NONE1", "title" => "T" },
    }

    client = fake_client.new(
      product_index: "prod_idx",
      offer_index: "offer_idx",
      product_docs: { "B00NONE1" => pdoc },
      offer_docs: {},
      offer_index_exists: false,
    )

    build_formatter.run!(client: client)

    expect(File.read(output_file).strip).to(eq(""))
    no_offer = File.read(File.join(emitter_dir, "no_offer_asins.txt")).lines.map(&:strip)
    expect(no_offer).to(include("B00NONE1"))
  end

  it "with skip_offers, takes price from product _source" do
    File.write(products_file, "B00SKIP1\n")

    pdoc = {
      "found" => true,
      "_id" => "B00SKIP1",
      "_source" => {
        "asin" => "B00SKIP1",
        "title" => "Skip Offers",
        "price" => 55.5,
        "currency" => "USD",
      },
    }

    client = fake_client.new(
      product_index: "prod_idx",
      offer_index: "offer_idx",
      product_docs: { "B00SKIP1" => pdoc },
      offer_docs: {},
      offer_index_exists: true,
    )

    build_formatter(skip_offers: true).run!(client: client)

    expect(client.offer_mgets).to(be_empty)

    row = JSON.parse(File.read(output_file).lines.first)
    expect(row["price"]).to(eq(55.5))
    expect(row["currency"]).to(eq("USD"))
  end

  context "with sink_index (--to-es)" do
    let(:pdoc) do
      {
        "found" => true,
        "_id" => "B00ES001",
        "_source" => { "asin" => "B00ES001", "title" => "ES Test", "price" => 9.0, "currency" => "USD" },
      }
    end

    it "bulk-indexes formatted rows into the sink index using ASIN as _id" do
      File.write(products_file, "B00ES001\n")
      client = fake_client.new(
        product_index: "prod_idx",
        offer_index: "offer_idx",
        product_docs: { "B00ES001" => pdoc },
        offer_docs: {},
        offer_index_exists: true,
      )

      formatter = build_formatter(
        output_path: nil,
        sink_index: "uploadable_products_us",
        skip_offers: true,
        sink_refresh: true,
      )
      formatter.run!(client: client)

      expect(client.bulk_bodies.size).to(eq(1))
      action_line, doc_line = client.bulk_bodies.first.split("\n").reject(&:empty?)
      action = JSON.parse(action_line)
      doc = JSON.parse(doc_line)
      expect(action.dig("index", "_index")).to(eq("uploadable_products_us"))
      expect(action.dig("index", "_id")).to(eq("B00ES001"))
      expect(doc["price"]).to(eq(9.0))
      expect(client.refreshed).to(eq(["uploadable_products_us"]))
      expect(formatter.record["es_indexed_count"]).to(eq(1))
      expect(formatter.record["es_bulk_requests"]).to(eq(1))
    end

    it "writes to file AND ES when both sinks are configured" do
      File.write(products_file, "B00ES001\n")
      client = fake_client.new(
        product_index: "prod_idx",
        offer_index: "offer_idx",
        product_docs: { "B00ES001" => pdoc },
        offer_docs: {},
        offer_index_exists: true,
      )

      build_formatter(sink_index: "uploadable_products_us", skip_offers: true).run!(client: client)

      lines = File.read(output_file).lines.map(&:strip).reject(&:empty?)
      expect(lines.size).to(eq(1))
      expect(client.bulk_bodies.size).to(eq(1))
    end

    it "flushes in chunks based on sink_bulk_chunk_lines" do
      File.write(products_file, "B00ES001\nB00ES002\nB00ES003\n")
      docs = {
        "B00ES001" => pdoc,
        "B00ES002" => pdoc.merge("_id" => "B00ES002", "_source" => pdoc["_source"].merge("asin" => "B00ES002")),
        "B00ES003" => pdoc.merge("_id" => "B00ES003", "_source" => pdoc["_source"].merge("asin" => "B00ES003")),
      }
      client = fake_client.new(
        product_index: "prod_idx",
        offer_index: "offer_idx",
        product_docs: docs,
        offer_docs: {},
        offer_index_exists: true,
      )

      build_formatter(
        output_path: nil,
        sink_index: "uploadable_products_us",
        sink_bulk_chunk_lines: 2,
        skip_offers: true,
      ).run!(client: client)

      expect(client.bulk_bodies.size).to(eq(2))
    end

    it "with dry_run, does not call bulk but still writes the file" do
      File.write(products_file, "B00ES001\n")
      client = fake_client.new(
        product_index: "prod_idx",
        offer_index: "offer_idx",
        product_docs: { "B00ES001" => pdoc },
        offer_docs: {},
        offer_index_exists: true,
      )

      formatter = build_formatter(
        sink_index: "uploadable_products_us",
        sink_refresh: true,
        skip_offers: true,
        dry_run: true,
      )
      formatter.run!(client: client)

      expect(client.bulk_bodies).to(be_empty)
      expect(client.refreshed).to(be_empty)
      expect(File.read(output_file).lines.size).to(eq(1))
      expect(formatter.record["es_bulk_requests"]).to(eq(0))
    end

    it "raises when neither output_path nor sink_index is set" do
      expect do
        described_class.new(
          marketplace: "us",
          products_path: products_file,
          source: "SRC",
          source_code: "SCODE",
        )
      end.to(raise_error(ArgumentError, /output_path or sink_index/))
    end
  end
end
