# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Oliveyoung::Queries::ProductsQuery) do
  it "produces the user's intended bool.filter[term:source=oliveyoung] shape" do
    expect(described_class.new.to_h).to(eq({
      bool: { filter: [{ term: { source: "oliveyoung" } }] },
    }))
  end

  it "honours an overridden source value" do
    expect(described_class.new(source_value: "OLIVEYOUNG").to_h).to(eq({
      bool: { filter: [{ term: { source: "OLIVEYOUNG" } }] },
    }))
  end

  it "honours an overridden source field (e.g. .keyword subfield)" do
    expect(described_class.new(source_field: "source.keyword").to_h).to(eq({
      bool: { filter: [{ term: { "source.keyword" => "oliveyoung" } }] },
    }))
  end

  it "merges extra filter clauses after the source term" do
    extra = EmTools::Core::Es::Query.range(:time, gte: "now-24h")
    expect(described_class.new(extra_filters: [extra]).to_h).to(eq({
      bool: {
        filter: [
          { term: { source: "oliveyoung" } },
          { range: { time: { gte: "now-24h" } } },
        ],
      },
    }))
  end
end
