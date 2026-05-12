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

  describe "plugin namespace contract" do
    let(:command_class) { Class.new { def run(_argv); end } }

    let(:fake_registry) do
      Module.new.tap do |mod|
        plugins = []
        mod.define_singleton_method(:add) { |plugin| plugins << plugin }
        mod.define_singleton_method(:each_plugin) { |&block| plugins.each(&block) }
      end
    end

    def plugin_double(name:, namespace:, commands:)
      instance_double(
        EmTools::Core::Plugin::Base,
        name: name,
        cli_namespace: namespace,
        cli_commands: commands,
      )
    end

    it "raises when a plugin command is missing the namespace prefix" do
      bad = plugin_double(name: :rogue, namespace: "rogue", commands: { "do-thing" => command_class })
      fake_registry.add(bad)

      expect { described_class.new(plugin_registry: fake_registry) }
        .to(raise_error(described_class::InvalidPluginCommandError, /must start with "rogue:"/))
    end

    it "registers correctly-namespaced plugin commands" do
      good = plugin_double(name: :good, namespace: "good", commands: { "good:do-thing" => command_class })
      fake_registry.add(good)

      registry = described_class.new(plugin_registry: fake_registry)

      expect(registry.fetch("good:do-thing").klass).to(eq(command_class))
    end
  end

  describe "#sections" do
    let(:command_class) { Class.new { def run(_argv); end } }

    let(:fake_registry) do
      Module.new.tap do |mod|
        plugins = []
        mod.define_singleton_method(:add) { |plugin| plugins << plugin }
        mod.define_singleton_method(:each_plugin) { |&block| plugins.each(&block) }
      end
    end

    it "groups plugin commands into one section per plugin, sorted by plugin name" do
      a = instance_double(
        EmTools::Core::Plugin::Base,
        name: :alpha,
        cli_namespace: "alpha",
        cli_commands: { "alpha:one" => command_class, "alpha:two" => command_class },
      )
      b = instance_double(
        EmTools::Core::Plugin::Base,
        name: :beta,
        cli_namespace: "beta",
        cli_commands: { "beta:run" => command_class },
      )
      fake_registry.add(b)
      fake_registry.add(a)

      sections = described_class.new(plugin_registry: fake_registry).sections
      plugin_titles = sections.map(&:first).select { |t| t.start_with?("Plugin:") }

      expect(plugin_titles).to(eq([
        "Plugin: alpha (alpha:*)",
        "Plugin: beta (beta:*)",
      ]))
    end
  end
end
