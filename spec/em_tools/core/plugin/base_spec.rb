# frozen_string_literal: true

require "spec_helper"

# Defined globally so RuboCop's Lint/ConstantDefinitionInBlock cop is not triggered.
class CorePluginBaseSpecDummyPlugin < EmTools::Core::Plugin::Base; end
class CorePluginBaseSpecHttpApiClient < EmTools::Core::Plugin::Base; end

class CorePluginBaseSpecKebabOverride < EmTools::Core::Plugin::Base
  def self.cli_namespace = "acme-cli"
end

RSpec.describe(EmTools::Core::Plugin::Base) do
  # Pokes +plugin_name=+ directly so these examples don't depend on
  # PluginRegistry — the registry's contract is covered in
  # plugin_registry_spec. Mutating shared classes like
  # CorePluginBaseSpecDummyPlugin is safe because every example resets
  # the value it sets.

  describe ".plugin_name" do
    it "is nil until set explicitly (no derivation from Ruby class name)" do
      expect(CorePluginBaseSpecHttpApiClient.plugin_name).to(be_nil)
    end

    it "is writable via plugin_name=" do
      CorePluginBaseSpecDummyPlugin.plugin_name = :explicit_test_a
      expect(CorePluginBaseSpecDummyPlugin.plugin_name).to(eq(:explicit_test_a))
    ensure
      CorePluginBaseSpecDummyPlugin.plugin_name = nil
    end
  end

  describe ".cli_namespace" do
    it "kebab-cases the explicit plugin_name" do
      CorePluginBaseSpecDummyPlugin.plugin_name = :my_explicit_plugin
      expect(CorePluginBaseSpecDummyPlugin.cli_namespace).to(eq("my-explicit-plugin"))
      expect(CorePluginBaseSpecDummyPlugin.new.cli_namespace).to(eq("my-explicit-plugin"))
    ensure
      CorePluginBaseSpecDummyPlugin.plugin_name = nil
    end

    it "raises NotRegisteredError when called with no plugin_name set" do
      expect { CorePluginBaseSpecHttpApiClient.cli_namespace }
        .to(raise_error(EmTools::Core::Plugin::NotRegisteredError, /plugin_name/))
    end

    it "honours subclass overrides without needing plugin_name" do
      expect(CorePluginBaseSpecKebabOverride.cli_namespace).to(eq("acme-cli"))
    end
  end

  describe "instance defaults" do
    let(:plugin) { described_class.new }

    it "returns empty arrays for filters and transforms" do
      expect(plugin.filters).to(eq([]))
      expect(plugin.transforms).to(eq([]))
    end

    it "returns nil for source and sink" do
      expect(plugin.source).to(be_nil)
      expect(plugin.sink).to(be_nil)
    end

    it "returns empty hashes for capabilities and dependencies" do
      expect(plugin.capabilities).to(eq({}))
      expect(plugin.dependencies).to(eq({}))
    end

    it "returns an empty hash for cli_commands" do
      expect(plugin.cli_commands).to(eq({}))
    end
  end
end
