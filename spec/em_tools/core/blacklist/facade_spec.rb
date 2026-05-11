# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe(EmTools::Core::Blacklist) do
  let(:rules_file) do
    Tempfile.new(["blacklist-source-rules", ".yml"]).tap do |file|
      file.write(<<~YAML)
        sources:
          product_download:
            strategy: title_brand
            options:
              title_field: title
              brand_field: brand
              case_sensitive: false
      YAML
      file.flush
    end
  end

  after { rules_file.close! }

  it "builds the source strategy selected by source_rules.yml" do
    strategy = described_class.build(
      keywords: ["Bonafide"],
      rules_source: "product_download",
      rules_path: rules_file.path,
    )

    expect(strategy).to(be_a(EmTools::Core::Blacklist::Strategy::TitleBrand))
    expect(strategy.blocked?("title" => "Bonafide gummy", "brand" => "Acme")).to(be(true))
  end

  it "exposes allow?/blocked?/matched as the stable API" do
    source = { "title" => "Bonafide gummy", "brand" => "Acme" }

    expect(described_class.allow?(
      source,
      keywords: ["Bonafide"],
      rules_path: rules_file.path,
    )).to(be(false))
    expect(described_class.blocked?(
      source,
      keywords: ["Bonafide"],
      rules_path: rules_file.path,
    )).to(be(true))
    expect(described_class.matched(
      source,
      keywords: ["Bonafide"],
      rules_path: rules_file.path,
    )).to(eq(["bonafide"]))
  end

  it "lets callers override source-rule options without losing the configured strategy" do
    strategy = described_class.build(
      keywords: ["Bonafide"],
      rules_path: rules_file.path,
      overrides: {
        "options" => {
          "title_field" => "title_en",
          "brand_field" => "manufacturer",
        },
      },
    )

    expect(strategy.blocked?("title_en" => "Bonafide gummy", "manufacturer" => "X")).to(be(true))
  end
end
