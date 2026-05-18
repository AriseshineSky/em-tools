# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe(EmTools::Plugins::GoogleAds::Catalog::MissingProductIdsExporter) do
  let(:es) { instance_double(EmTools::Clients::ElasticsearchClient) }

  def hit(id)
    { "_source" => { "source_product_id" => id, "source" => "AMZ_DE" } }
  end

  before do
    allow(es).to(receive(:index_exists?).and_return(true))
  end

  it "writes inventory-only source_product_id values to the output file" do
    allow(es).to(receive(:iterate_query)) do |index:, query:, batch_size:, max_hits: nil, &blk| # rubocop:disable Lint/UnusedBlockArgument
      hits =
        if index == "em_inventory"
          [hit("B001"), hit("B002"), hit("B003")]
        else
          [hit("B001"), hit("B999")]
        end
      hits.each(&blk)
      hits.size
    end

    Dir.mktmpdir do |dir|
      path = File.join(dir, "missing.txt")
      summary = described_class.new(es_client: es, source: "amz_de").export!(path)

      expect(summary[:missing_ids]).to(eq(2))
      body = File.read(path)
      expect(body).to(include("B002"))
      expect(body).to(include("B003"))
      expect(body.lines.grep(/^B001$/)).to(be_empty)
    end
  end

  it "raises when the inventory index does not exist" do
    allow(es).to(receive(:index_exists?).with("em_inventory").and_return(false))

    expect do
      described_class.new(es_client: es, source: "AMZ_DE").export!("/tmp/x.txt")
    end.to(raise_error(EmTools::Core::Errors::ConfigurationError, /not found: em_inventory/))
  end
end
