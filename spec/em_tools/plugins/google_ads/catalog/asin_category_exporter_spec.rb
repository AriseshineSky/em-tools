# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe(EmTools::Plugins::GoogleAds::Catalog::AsinCategoryExporter) do
  let(:es) { instance_double(EmTools::Clients::ElasticsearchClient) }

  before do
    allow(es).to(receive(:index_exists?).with("amz_products_api_de_v2").and_return(true))
  end

  it "writes first categories[] entry per ASIN as TSV" do
    allow(es).to(receive(:mget).with(
      index: "amz_products_api_de_v2",
      ids: %w[B001 B002 B003],
    ).and_return(
      "docs" => [
        {
          "_id" => "B001",
          "found" => true,
          "_source" => {
            "categories" => [{ "cat_name" => "Health & Personal Care", "cat_id" => "64187031" }],
          },
        },
        { "_id" => "B002", "found" => false },
        {
          "_id" => "B003",
          "found" => true,
          "_source" => { "categories" => [] },
        },
      ],
    ))

    Dir.mktmpdir do |dir|
      input = File.join(dir, "in.txt")
      File.write(input, "# test\nB001\nB002\nB003\n")

      out = File.join(dir, "out.tsv")
      summary = described_class.new(es_client: es, product_index: "amz_products_api_de_v2").export!(
        input_path: input,
        output_path: out,
      )

      expect(summary[:found]).to(eq(1))
      expect(summary[:missing]).to(eq(1))
      expect(summary[:no_category]).to(eq(1))

      lines = File.read(out).lines(chomp: true)
      expect(lines[0]).to(eq("asin\tcat_id\tcat_name\tstatus"))
      expect(lines[1]).to(eq("B001\t64187031\tHealth & Personal Care\tok"))
      expect(lines[2]).to(eq("B002\t\t\tnot_found"))
      expect(lines[3]).to(eq("B003\t\t\tno_category"))
    end
  end
end
