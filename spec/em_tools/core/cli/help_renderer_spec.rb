# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Cli::HelpRenderer) do
  describe "#render" do
    it "renders help from registry sections" do
      registry = EmTools::Core::Cli::CommandRegistry.new
      output = described_class.new(registry: registry).render

      expect(output).to(include("em-tools — Everymarket data platform CLI"))
      expect(output).to(include("Inventory & object storage"))
      expect(output).to(include("inventory-sync"))
      expect(output).to(match(/Plugin: \w+ \(\S+:\*\)/))
    end
  end
end
