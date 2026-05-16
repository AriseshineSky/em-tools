# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Cli::Registry) do
  before { described_class.reset! }
  after { described_class.reset! }

  describe ".build" do
    it "registers core commands at hierarchical paths" do
      registry = described_class.build

      command = registry.get(["inventory", "sync"])
      expect(command).to(be_found)
      expect(command.command).to(eq(EmTools::Core::Cli::Commands::InventorySync))
    end

    it "registers blacklist download under the 'blacklist' subtree" do
      registry = described_class.build
      command = registry.get(["blacklist", "download"])

      expect(command).to(be_found)
      expect(command.command).to(eq(EmTools::Core::Cli::Commands::BlacklistDownload))
    end

    it "registers es translate-titles under the es subtree" do
      registry = described_class.build
      command = registry.get(["es", "translate-titles"])

      expect(command).to(be_found)
      expect(command.command).to(eq(EmTools::Core::Cli::Commands::EsTranslateTitles))
    end

    it "registers lazada products commands under lazada subtree" do
      registry = described_class.build
      cmd = registry.get(["lazada", "products", "build-upload"])
      expect(cmd).to(be_found)
      expect(cmd.command).to(eq(EmTools::Plugins::Lazada::Cli::BuildUpload))
    end

    it "is memoised across calls" do
      first = described_class.build
      second = described_class.build

      expect(second).to(equal(first))
    end

    it "rebuilds after reset!" do
      first = described_class.build
      described_class.reset!
      second = described_class.build

      expect(second).not_to(equal(first))
    end

    it "registers plugin commands under the plugin's cli_namespace" do
      registry = described_class.build

      filter = registry.get(["amazon", "products", "filter"])
      expect(filter).to(be_found)
      expect(filter.command).to(eq(EmTools::Plugins::Amazon::Uploadable::Cli::UploadableProductFilter))

      coverage = registry.get(["amazon", "coverage", "publish-snapshot"])
      expect(coverage).to(be_found)
      expect(coverage.command).to(eq(EmTools::Plugins::Amazon::LowestOffer::Cli::PublishSnapshot))
    end
  end
end
