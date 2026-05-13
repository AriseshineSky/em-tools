# frozen_string_literal: true

require "spec_helper"

# Defined globally so RuboCop's Lint/ConstantDefinitionInBlock cop is not triggered.
class CorePluginBaseSpecAmazonUploadable < EmTools::Core::Plugin::Base; end
class CorePluginBaseSpecHttpApiClient < EmTools::Core::Plugin::Base; end

RSpec.describe(EmTools::Core::Plugin::Base) do
  describe ".plugin_name" do
    it "snake_cases CamelCase class names" do
      expect(CorePluginBaseSpecAmazonUploadable.plugin_name).to(eq(:core_plugin_base_spec_amazon_uploadable))
    end

    it "handles consecutive capitals" do
      expect(CorePluginBaseSpecHttpApiClient.plugin_name).to(eq(:core_plugin_base_spec_http_api_client))
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

  describe ".cli_namespace" do
    it "kebab-cases the plugin name by default" do
      expect(CorePluginBaseSpecAmazonUploadable.cli_namespace)
        .to(eq("core-plugin-base-spec-amazon-uploadable"))
    end

    it "is also accessible on instances" do
      expect(CorePluginBaseSpecAmazonUploadable.new.cli_namespace)
        .to(eq("core-plugin-base-spec-amazon-uploadable"))
    end
  end
end
