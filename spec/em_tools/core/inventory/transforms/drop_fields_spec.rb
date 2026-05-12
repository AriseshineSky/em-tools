# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Inventory::Transforms::DropFields) do
  it "removes the listed fields and returns the same hash" do
    doc = { "product_id" => "1", "handle" => "foo", "variants" => [], "price" => "9.99" }

    out = described_class.new("handle", "variants").call(doc)

    expect(out).to(equal(doc))
    expect(out).to(eq("product_id" => "1", "price" => "9.99"))
  end

  it "is a no-op when fields list is empty" do
    doc = { "a" => 1 }
    out = described_class.new.call(doc)
    expect(out).to(eq("a" => 1))
  end

  it "ignores fields that aren't on the doc" do
    doc = { "product_id" => "1" }
    out = described_class.new("handle", "variants").call(doc)
    expect(out).to(eq("product_id" => "1"))
  end

  it "accepts symbols and arrays interchangeably and normalizes them to strings" do
    doc = { "handle" => "x", "variants" => [], "keep" => 1 }
    out = described_class.new(:handle, ["variants"]).call(doc)
    expect(out).to(eq("keep" => 1))
  end

  it "exposes the resolved field list via #fields" do
    expect(described_class.new("handle", " variants ", "").fields).to(eq(["handle", "variants"]))
  end
end
