# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Cli::CommandRegistry) do
  describe "#command_table" do
    it "includes core data-platform commands" do
      table = described_class.new.command_table

      expect(table).to(include(
        "inventory-sync" => EmTools::Core::Cli::Commands::InventorySync,
        "lowest-offer-publish-snapshot" => EmTools::Core::Cli::Commands::LowestOfferPublishSnapshot,
        "dump" => EmTools::Core::Cli::Commands::Dump,
        "blacklist-download" => EmTools::Core::Cli::Commands::BlacklistDownload,
      ))
    end
  end

  describe "#fetch" do
    it "resolves namespace-style aliases to the canonical command" do
      command = described_class.new.fetch("inventory:sync")

      expect(command.name).to(eq("inventory-sync"))
      expect(command.klass).to(eq(EmTools::Core::Cli::Commands::InventorySync))
    end

    it "resolves the blacklist namespace alias" do
      command = described_class.new.fetch("blacklist:download")

      expect(command.name).to(eq("blacklist-download"))
      expect(command.klass).to(eq(EmTools::Core::Cli::Commands::BlacklistDownload))
    end
  end

  describe ".default" do
    it "caches the registry instance" do
      described_class.reset_default!

      first = described_class.default
      second = described_class.default

      expect(second).to(be(first))
    ensure
      described_class.reset_default!
    end
  end
end
