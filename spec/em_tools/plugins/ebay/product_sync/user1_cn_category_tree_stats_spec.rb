# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe EmTools::Plugins::Ebay::ProductSync::CategoryPathParser do
  it "uses the whole string as level1 when no separator is present" do
    expect(described_class.level1("Tech & Electronics")).to eq("Tech & Electronics")
    expect(described_class.level2_path("Tech & Electronics")).to eq("Tech & Electronics")
  end

  it "splits on > and keeps commas inside level names" do
    raw = "Home, Garden & Tools>Kitchen &  Dining>Sub"
    expect(described_class.level1(raw)).to eq("Home, Garden & Tools")
    expect(described_class.level2_path(raw)).to eq("Home, Garden & Tools>Kitchen &  Dining")
  end

  it "returns missing labels for blank values" do
    expect(described_class.level1(nil)).to eq("(missing categories)")
    expect(described_class.level2_path("   ")).to eq("(missing categories)")
  end
end

RSpec.describe EmTools::Plugins::Ebay::ProductSync::User1CnCategoryTreeStats do
  let(:es) { instance_double(EmTools::Clients::ElasticsearchClient) }

  it "writes level1 and level2 TSV files from a scan fallback" do
    allow(es).to receive(:index_exists?).with("user1_cn_products").and_return(true)
    allow(es).to receive(:search).and_return(
      { "hits" => { "total" => { "value" => 3 } } },
      { "aggregations" => { "by_category" => { "buckets" => [] } } },
      { "aggregations" => { "by_category" => { "buckets" => [] } } },
    )

    hits = [
      { "_source" => { "categories" => "Home, Garden & Tools>Kitchen &  Dining" } },
      { "_source" => { "categories" => "Home, Garden & Tools>Home Improvement>Tools" } },
      { "_source" => { "categories" => "Tech & Electronics" } },
    ]
    expect(es).to receive(:iterate_query) do |**, &block|
      hits.each(&block)
    end

    dir = File.join(Dir.tmpdir, "user1_cn_category_stats_spec_#{Process.pid}")
    FileUtils.rm_rf(dir)

    stats = described_class.new(es_client: es, source: "inspireuplift").export!(output_dir: dir)

    expect(stats.total_docs).to eq(3)
    expect(stats.method).to eq("scan")
    expect(File).to exist(File.join(dir, "level1.tsv"))
    expect(File).to exist(File.join(dir, "level2.tsv"))
    level1 = File.read(File.join(dir, "level1.tsv"))
    expect(level1).to include("Home, Garden & Tools\t2")
    expect(level1).to include("Tech & Electronics\t1")
    level2 = File.read(File.join(dir, "level2.tsv"))
    expect(level2).to include("Home, Garden & Tools>Kitchen &  Dining\t1")
    expect(level2).to include("Home, Garden & Tools>Home Improvement\t1")
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
