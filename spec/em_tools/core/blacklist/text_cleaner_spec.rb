# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Blacklist::TextCleaner) do
  describe ".clean_separators" do
    it "replaces registered trademark with a space" do
      expect(described_class.clean_separators("ARK® Biting and Chewing"))
        .to(eq("ARK  Biting and Chewing"))
    end

    it "replaces common punctuation separators like Python _SEPARATOR_RE" do
      expect(described_class.clean_separators("foo-bar|baz"))
        .to(eq("foo bar baz"))
    end
  end
end
