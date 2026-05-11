# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Storefront::Runners::UnpublishCandidates) do
  let(:es) { FakeUnpublishEs.new }

  let(:always_pass_filter) do
    Class.new do
      def check(_doc) = { passed: true, reason: "", message: "" }
    end.new
  end

  let(:battery_filter) do
    Class.new do
      def check(doc)
        bi = doc.dig("attributes", "batteries_included") || []
        if Array(bi).any? { |x| x.is_a?(Hash) && x["value"] == true }
          { passed: false, reason: "[IncludeBattery]", message: "has batteries" }
        else
          { passed: true, reason: "", message: "" }
        end
      end
    end.new
  end

  it "flags products that fail a rule and bulk-indexes them with stable doc ids" do
    es.add_inventory_row("B00CLEAN", source: "AMZ_US", product_id: "111")
    es.add_inventory_row("B00BATTRY", source: "AMZ_US", product_id: "222")
    es.add_product(
      "amz_products_api_us_v2",
      "B00CLEAN",
      { "attributes" => { "batteries_included" => [{ "value" => false }] } },
    )
    es.add_product(
      "amz_products_api_us_v2",
      "B00BATTRY",
      { "attributes" => { "batteries_included" => [{ "value" => true }] } },
    )

    runner = described_class.new(
      es_client: es,
      filters: [battery_filter],
      sources: ["AMZ_US"],
      refresh: false,
    )
    stats = runner.run!

    expect(stats[:evaluated]).to(eq(2))
    expect(stats[:flagged]).to(eq(1))
    expect(stats[:by_source]).to(eq("AMZ_US" => 1))
    expect(stats[:by_reason]).to(eq("[IncludeBattery]" => 1))

    indexed = es.indexed_records("em_products_to_unpublish")
    expect(indexed.keys).to(eq(["AMZ_US::B00BATTRY"]))
    expect(indexed["AMZ_US::B00BATTRY"]).to(include(
      "product_id" => "222",
      "source" => "AMZ_US",
      "source_product_id" => "B00BATTRY",
      "marketplace" => "us",
      "reason" => "[IncludeBattery]",
    ))
  end

  it "flags rows whose product doc is missing as [NotExist]" do
    es.add_inventory_row("B00MISS", source: "AMZ_CA", product_id: "999")
    runner = described_class.new(
      es_client: es,
      filters: [always_pass_filter],
      sources: ["AMZ_CA"],
      refresh: false,
    )
    stats = runner.run!

    expect(stats[:flagged]).to(eq(1))
    expect(stats[:missing_product_doc]).to(eq(1))
    indexed = es.indexed_records("em_products_to_unpublish")
    expect(indexed["AMZ_CA::B00MISS"]["reason"]).to(eq("[NotExist]"))
  end

  it "respects max_evaluated as a hard cap" do
    5.times do |i|
      es.add_inventory_row("B00#{i}", source: "AMZ_US", product_id: i.to_s)
      es.add_product("amz_products_api_us_v2", "B00#{i}", { "attributes" => {} })
    end
    runner = described_class.new(
      es_client: es,
      filters: [always_pass_filter],
      sources: ["AMZ_US"],
      max_evaluated: 2,
      refresh: false,
    )
    stats = runner.run!
    expect(stats[:evaluated]).to(be <= 2)
  end

  it "skips inventory rows whose source has no resolver" do
    es.add_inventory_row("X", source: "Boyner", product_id: "b1")
    runner = described_class.new(
      es_client: es,
      filters: [always_pass_filter],
      sources: ["Boyner"],
      product_index_resolver: ->(_src) { nil },
      refresh: false,
    )
    stats = runner.run!
    expect(stats[:skipped_unsupported_source]).to(eq(1))
    expect(stats[:flagged]).to(eq(0))
  end
end

# Minimal Elasticsearch double that the UnpublishCandidates runner can drive end-to-end.
class FakeUnpublishEs
  def initialize
    @rows_by_source = Hash.new { |h, k| h[k] = [] }
    @products = Hash.new { |h, k| h[k] = {} }
    @indexed = Hash.new { |h, k| h[k] = {} }
    @existing_indices = []
  end

  def add_inventory_row(asin, source:, product_id:)
    @rows_by_source[source] << {
      "_id" => "#{source}::#{asin}",
      "_source" => {
        "product_id" => product_id, "source" => source, "source_product_id" => asin,
      },
    }
  end

  def add_product(index, asin, source_doc)
    @products[index][asin] = source_doc
    @existing_indices << index unless @existing_indices.include?(index)
  end

  def index_exists?(name)
    @existing_indices.include?(name) || name == "em_products_to_unpublish"
  end

  def create_index(_name, **); end

  def search(index:, body:, **)
    return search_inventory_aggregation if body[:size].to_i.zero? && body.dig(:aggs, :sources)

    raise "unsupported fake search index=#{index}"
  end

  def search_inventory_aggregation
    buckets = @rows_by_source.keys.map { |k| { "key" => k, "doc_count" => @rows_by_source[k].size } }
    { "aggregations" => { "sources" => { "buckets" => buckets } } }
  end

  def iterate_query(index:, query:, **, &block)
    raise "unsupported" unless index == "em_inventory"

    src = query.dig(:term, "source.keyword")
    @rows_by_source[src].each(&block)
  end

  def mget(index:, ids:, **)
    docs = ids.map do |id|
      doc = @products[index][id]
      if doc
        { "_id" => id, "found" => true, "_source" => doc }
      else
        { "_id" => id, "found" => false }
      end
    end
    { "docs" => docs }
  end

  def bulk(body:)
    body.each_slice(2) do |action, doc|
      target = action["index"]["_index"]
      id = action["index"]["_id"]
      @indexed[target][id] = doc
    end
    { "errors" => false, "items" => [] }
  end

  def refresh(*); end

  def indexed_records(index)
    @indexed[index]
  end
end
