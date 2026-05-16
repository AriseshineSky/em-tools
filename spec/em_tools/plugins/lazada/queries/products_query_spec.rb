# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Lazada::Queries::ProductsQuery) do
  it "uses match_all when source_value is blank and no extra filters" do
    expect(described_class.new(source_value: nil).to_h).to(eq({ match_all: {} }))
    expect(described_class.new(source_value: "").to_h).to(eq({ match_all: {} }))
    expect(described_class.new(source_value: "   ").to_h).to(eq({ match_all: {} }))
  end

  it "adds a term filter when source_value is present" do
    q = described_class.new(source_value: "lazadacoth").to_h
    expect(q).to(eq({
      bool: {
        filter: [{ term: { source: "lazadacoth" } }],
      },
    }))
  end

  it "merges extra_filters" do
    extra = [{ exists: { field: "product_id" } }]
    q = described_class.new(source_value: "x", extra_filters: extra).to_h
    expect(q[:bool][:filter].size).to(eq(2))
  end

  it "uses bool filter when only extra_filters are present" do
    extra = [{ exists: { field: "product_id" } }]
    q = described_class.new(source_value: nil, extra_filters: extra).to_h
    expect(q).to(eq({ bool: { filter: extra } }))
  end
end
