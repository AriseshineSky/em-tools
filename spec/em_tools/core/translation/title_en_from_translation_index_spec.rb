# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Translation::TitleEnFromTranslationIndex) do
  let(:fake_es) do
    Class.new do
      attr_reader :mget_calls

      def initialize(map)
        @map = map
        @mget_calls = []
      end

      def mget(index:, ids:, **)
        @mget_calls << { index: index, ids: ids }
        docs = ids.map do |id|
          src = @map[id]
          if src
            { "found" => true, "_source" => src }
          else
            { "found" => false }
          end
        end
        { "docs" => docs }
      end
    end
  end

  let(:map) do
    {
      EmTools::Core::Translation::DocId.encode("oliveyoung", "P1") => { "title_en" => "Hello EN" },
    }
  end

  it "merges title_en when a translation row exists" do
    es = fake_es.new(map)
    merger = described_class.new(
      es_client: es,
      translation_index: "em_title_translations",
      source_field: "source",
      source_product_id_field: "source_product_id",
    )
    out = merger.enrich("source" => "oliveyoung", "source_product_id" => "P1", "title" => "안녕")
    expect(out["title_en"]).to(eq("Hello EN"))
    expect(es.mget_calls.size).to(eq(1))
  end

  it "memoizes mget per id within one exporter run" do
    es = fake_es.new(map)
    merger = described_class.new(es_client: es, translation_index: "t")
    2.times do
      merger.enrich("source" => "oliveyoung", "source_product_id" => "P1")
    end
    expect(es.mget_calls.size).to(eq(1))
  end

  it "returns the original hash when translation is missing" do
    es = fake_es.new({})
    merger = described_class.new(es_client: es, translation_index: "t")
    src = { "source" => "oliveyoung", "source_product_id" => "missing" }
    expect(merger.enrich(src)).to(equal(src))
  end

  it "compose_with chains enrich before inner call" do
    es = fake_es.new(map)
    inner = proc { |src| src.merge("x" => 1) }
    composed = described_class.compose_with(
      inner: inner,
      product_es_client: es,
      translation_index: "em_title_translations",
    )
    out = composed.call("source" => "oliveyoung", "source_product_id" => "P1")
    expect(out["title_en"]).to(eq("Hello EN"))
    expect(out["x"]).to(eq(1))
  end
end
