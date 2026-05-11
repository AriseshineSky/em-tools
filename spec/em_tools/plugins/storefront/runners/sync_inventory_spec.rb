# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Storefront::Runners::SyncInventory) do
  let(:fake_sink) { FakeInventorySink.new }
  let(:fake_spree_api) { FakeSpreeApi.new }
  let(:product_util) do
    EmTools::Plugins::Storefront::ProductUtil.new("http://example", "tok", spree_api: fake_spree_api)
  end

  it "syncs each requested source via Core::Inventory::Sync and reports per-source status" do
    fake_spree_api.set_inventory_csv("AMZ_AE", <<~CSV)
      ProductID,Source,SourceProductID,Handle
      111,AMZ_AE,B00ONE,one
      222,AMZ_AE,B00TWO,two
    CSV
    fake_spree_api.set_inventory_csv("AMZ_CA", "")

    runner = described_class.new(
      product_util: product_util,
      sink: fake_sink,
      sources: ["AMZ_AE", "AMZ_CA"],
      refresh: false,
      prune_obsolete: false,
    )
    results = runner.run!

    expect(results["AMZ_AE"][:status]).to(eq(:synced))
    expect(results["AMZ_AE"][:byte_size]).to(be > 0)
    expect(results["AMZ_CA"][:status]).to(eq(:empty))

    indexed_ids = fake_sink.bulk_actions.flatten.filter_map { |op| op.dig(:update, :_id) }
    expect(indexed_ids).to(contain_exactly("111", "222"))
  end

  it "reports :error and continues when a source download raises" do
    fake_spree_api.fail_for("AMZ_AE", RuntimeError.new("boom"))
    fake_spree_api.set_inventory_csv("AMZ_CA", <<~CSV)
      ProductID,Source,SourceProductID,Handle
      999,AMZ_CA,B00CA,ca-handle
    CSV

    runner = described_class.new(
      product_util: product_util,
      sink: fake_sink,
      sources: ["AMZ_AE", "AMZ_CA"],
      refresh: false,
      prune_obsolete: false,
    )
    results = runner.run!

    expect(results["AMZ_AE"][:status]).to(eq(:error))
    expect(results["AMZ_AE"][:error]).to(include("boom"))
    expect(results["AMZ_CA"][:status]).to(eq(:synced))
  end
end

# Minimal SpreeClient stand-in that just writes an in-memory CSV string to the requested path.
class FakeSpreeApi
  def initialize
    @csv_by_source = {}
    @failures = {}
  end

  def set_inventory_csv(source, content)
    @csv_by_source[source] = content
  end

  def fail_for(source, exc)
    @failures[source] = exc
  end

  def download_inventory(source, output_path)
    raise @failures[source] if @failures.key?(source)

    File.write(output_path, @csv_by_source.fetch(source, ""))
  end
end

# Minimal ES sink double for these specs.
class FakeInventorySink
  attr_reader :bulk_actions

  def initialize
    @bulk_actions = []
  end

  def bulk(body:)
    @bulk_actions << body
    { "errors" => false }
  end

  def refresh(**); end

  def delete_by_query(**); end
end
