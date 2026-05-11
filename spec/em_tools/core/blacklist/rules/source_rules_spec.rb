# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe(EmTools::Core::Blacklist::Rules::SourceRules) do
  def rules_file(contents)
    Tempfile.new(["blacklist-rules", ".yml"]).tap do |file|
      file.write(contents)
      file.flush
    end
  end

  it "loads the rule for a known source" do
    file = rules_file(<<~YAML)
      sources:
        product_download:
          strategy: title_brand
          options:
            title_field: title
    YAML

    rules = described_class.load(path: file.path)

    expect(rules.fetch("product_download")).to(eq(
      "strategy" => "title_brand",
      "options" => {
        "title_field" => "title",
      },
    ))
  ensure
    file&.close!
  end

  it "raises a configuration error for an unknown source" do
    file = rules_file("sources: {}\n")

    expect { described_class.load(path: file.path).fetch("missing") }
      .to(raise_error(EmTools::Core::Errors::ConfigurationError, /Unknown blacklist source rules/))
  ensure
    file&.close!
  end

  it "raises a configuration error when the sources mapping is missing" do
    file = rules_file("not_sources: {}\n")

    expect { described_class.load(path: file.path) }
      .to(raise_error(EmTools::Core::Errors::ConfigurationError, /must contain a sources/))
  ensure
    file&.close!
  end
end
