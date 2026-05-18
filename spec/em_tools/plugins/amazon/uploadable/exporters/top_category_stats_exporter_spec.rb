# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe(EmTools::Plugins::Amazon::Uploadable::Exporters::TopCategoryStatsExporter) do
  let(:es) { instance_double(EmTools::Clients::ElasticsearchClient) }

  before do
    allow(es).to(receive(:index_exists?).with("amz_products_api_de_v2").and_return(true))
    allow(es).to(receive(:search)) do |body:, **|
      if body.dig(:aggs, :probe)
        { "aggregations" => { "probe" => { "buckets" => [{ "key" => "x", "doc_count" => 1 }] } } }
      else
        {
          "aggregations" => {
            "by_top_category" => {
              "buckets" => [
                { "key" => "Health & Personal Care", "doc_count" => 100 },
                { "key" => "Electronics", "doc_count" => 42 },
              ],
            },
          },
        }
      end
    end
  end

  it "writes top_category and doc_count as TSV and JSON" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "counts.tsv")
      summary = described_class.new(es_client: es, product_index: "amz_products_api_de_v2").export!(output_path: path)

      expect(summary[:categories]).to(eq(2))
      expect(summary[:documents]).to(eq(142))

      lines = File.read(path).lines(chomp: true)
      expect(lines[0]).to(eq("top_category\tdoc_count"))
      expect(lines[1]).to(eq("Health & Personal Care\t100"))

      json = JSON.parse(File.read(File.join(dir, "counts.json")))
      expect(json["rows"].first["top_category"]).to(eq("Health & Personal Care"))
    end
  end
end
