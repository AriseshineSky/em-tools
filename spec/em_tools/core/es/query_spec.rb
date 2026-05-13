# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Es::Query) do
  describe ".match_all" do
    it "returns the canonical match_all clause" do
      expect(described_class.match_all).to(eq({ match_all: {} }))
    end
  end

  describe ".term" do
    it "wraps a single field/value as a term clause" do
      expect(described_class.term(:source, "oliveyoung")).to(eq({ term: { source: "oliveyoung" } }))
    end

    it "preserves string keys verbatim (e.g. .keyword subfields)" do
      expect(described_class.term("asin.keyword", "B0001"))
        .to(eq({ term: { "asin.keyword" => "B0001" } }))
    end
  end

  describe ".terms" do
    it "wraps multiple values" do
      expect(described_class.terms(:source, ["oliveyoung", "ssg"]))
        .to(eq({ terms: { source: ["oliveyoung", "ssg"] } }))
    end

    it "coerces a scalar to a single-element array" do
      expect(described_class.terms(:source, "oliveyoung"))
        .to(eq({ terms: { source: ["oliveyoung"] } }))
    end
  end

  describe ".range" do
    it "passes bounds through unchanged" do
      expect(described_class.range(:time, gte: "now-24h", lt: "now"))
        .to(eq({ range: { time: { gte: "now-24h", lt: "now" } } }))
    end
  end

  describe ".exists" do
    it "wraps a field name" do
      expect(described_class.exists(:source)).to(eq({ exists: { field: :source } }))
    end
  end

  describe ".bool" do
    it "drops empty clauses" do
      expect(described_class.bool(filter: [described_class.term(:source, "oliveyoung")]))
        .to(eq({ bool: { filter: [{ term: { source: "oliveyoung" } }] } }))
    end

    it "drops nil and empty inputs" do
      expect(described_class.bool(must: nil, filter: [], must_not: nil, should: []))
        .to(eq({ bool: {} }))
    end

    it "accepts all four clauses + minimum_should_match" do
      result = described_class.bool(
        must: [described_class.term(:a, 1)],
        filter: [described_class.term(:b, 2)],
        must_not: [described_class.term(:c, 3)],
        should: [described_class.term(:d, 4)],
        minimum_should_match: 1,
      )
      expect(result).to(eq({
        bool: {
          must: [{ term: { a: 1 } }],
          filter: [{ term: { b: 2 } }],
          must_not: [{ term: { c: 3 } }],
          should: [{ term: { d: 4 } }],
          minimum_should_match: 1,
        },
      }))
    end

    it "wraps a scalar clause as a single-element array" do
      result = described_class.bool(filter: described_class.term(:source, "oliveyoung"))
      expect(result).to(eq({ bool: { filter: [{ term: { source: "oliveyoung" } }] } }))
    end
  end
end
