# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Pipeline) do
  let(:strip_titles) do
    lambda do |row, _ctx|
      row.merge("title" => row["title"].to_s.strip)
    end
  end

  let(:drop_short_titles) do
    lambda do |row, _ctx|
      row["title"].length < 2 ? described_class::DROP : row
    end
  end

  it "threads context through and returns transformed record" do
    pipeline = described_class.new([strip_titles])
    ctx = { trace: true }
    out = pipeline.call({ "title" => "  hello  " }, ctx)
    expect(out).to(eq("title" => "hello"))
  end

  it "short-circuits on :drop" do
    called = false
    tail = lambda do |_row, _ctx|
      called = true
      { "ok" => true }
    end

    pipeline = described_class.new([drop_short_titles, tail])
    expect(pipeline.call({ "title" => "x" }, {})).to(eq(described_class::DROP))
    expect(called).to(be(false))
  end

  it "filter_map skips dropped rows" do
    pipeline = described_class.new([strip_titles, drop_short_titles])
    rows = [{ "title" => "  ab  " }, { "title" => "x" }, { "title" => " z " }]
    expect(pipeline.filter_map(rows, nil).force).to(eq([{ "title" => "ab" }]))
  end
end
