# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Translation::DocId) do
  it "is stable for the same inputs" do
    a = described_class.encode("oliveyoung", "SKU-1")
    b = described_class.encode("oliveyoung", "SKU-1")
    expect(a).to(eq(b))
    expect(a.length).to(eq(64))
  end

  it "changes when source or product id changes" do
    x = described_class.encode("oliveyoung", "SKU-1")
    y = described_class.encode("lotteon", "SKU-1")
    z = described_class.encode("oliveyoung", "SKU-2")
    expect(x).not_to(eq(y))
    expect(x).not_to(eq(z))
  end

  it "strips whitespace" do
    expect(described_class.encode("  oy  ", "  id  "))
      .to(eq(described_class.encode("oy", "id")))
  end
end
