# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::ProductFormatting::DescriptionFormatter) do
  describe ".remove_a_tag" do
    it "removes <a> tags and their children from an HTML fragment" do
      html = '<p>Read <a href="http://x">more</a> here</p>'
      out = described_class.remove_a_tag(html)
      expect(out).to(include("<p>"))
      expect(out).not_to(match(/<a\b/))
      expect(out).not_to(include("more"))
      expect(out).to(include("Read"))
      expect(out).to(include("here"))
    end

    it "returns nil for nil input" do
      expect(described_class.remove_a_tag(nil)).to(be_nil)
    end

    it "returns nil for an empty string" do
      expect(described_class.remove_a_tag("")).to(be_nil)
    end

    it "is idempotent under double application (lotteon / rakuten do this)" do
      html = '<div>x <a href="y">y</a> z</div>'
      once = described_class.remove_a_tag(html)
      twice = described_class.remove_a_tag(once)
      expect(twice).not_to(match(/<a\b/))
      expect(twice).to(include("z"))
    end

    it "handles malformed HTML without raising (Nokogiri is permissive)" do
      malformed = '<p>not closed <a href="z">link'
      expect { described_class.remove_a_tag(malformed) }.not_to(raise_error)
      expect(described_class.remove_a_tag(malformed)).not_to(match(/<a\b/))
    end
  end

  describe ".generate_description_by_specifications" do
    it "builds an unordered list of name/value items" do
      specs = [
        { "name" => "Color", "value" => "Red" },
        { "name" => "Size", "value" => "M" },
      ]
      expect(described_class.generate_description_by_specifications(specs)).to(eq(
        "<ul><li>Color: Red</li><li>Size: M</li></ul>",
      ))
    end

    it "skips items with empty name or value" do
      specs = [
        { "name" => "", "value" => "Red" },
        { "name" => "Size", "value" => "" },
        { "name" => "Color", "value" => "Blue" },
      ]
      expect(described_class.generate_description_by_specifications(specs)).to(eq(
        "<ul><li>Color: Blue</li></ul>",
      ))
    end

    it "returns empty string for nil / empty / non-Hash entries" do
      expect(described_class.generate_description_by_specifications(nil)).to(eq(""))
      expect(described_class.generate_description_by_specifications([])).to(eq(""))
      expect(described_class.generate_description_by_specifications([nil, "junk"])).to(eq(""))
    end

    it "HTML-escapes name and value to prevent description injection" do
      specs = [{ "name" => "Notes", "value" => "<script>alert(1)</script>" }]
      out = described_class.generate_description_by_specifications(specs)
      expect(out).to(include("&lt;script&gt;"))
      expect(out).not_to(include("<script>"))
    end
  end
end
