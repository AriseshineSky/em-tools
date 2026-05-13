# frozen_string_literal: true

require "spec_helper"

class PluginRegistrySpecPluginA < EmTools::Core::Plugin::Base
  def filters
    ["A"]
  end
end

class PluginRegistrySpecPluginB < EmTools::Core::Plugin::Base; end

RSpec.describe(EmTools::Core::PluginRegistry) do
  before do
    @snapshot = described_class.names.to_h { |n| [n, described_class.fetch_class(n)] }
    described_class.reset!
  end

  after do
    described_class.reset!
    @snapshot.each { |name, klass| described_class.register(name, klass) }
  end

  it "registers and fetches a plugin by name" do
    described_class.register(:a, PluginRegistrySpecPluginA)
    plugin = described_class.fetch(:a)
    expect(plugin).to(be_a(PluginRegistrySpecPluginA))
    expect(plugin.filters).to(eq(["A"]))
  end

  it "lists registered names" do
    described_class.register(:a, PluginRegistrySpecPluginA)
    described_class.register(:b, PluginRegistrySpecPluginB)
    expect(described_class.names).to(contain_exactly(:a, :b))
  end

  it "raises on unknown plugin" do
    expect { described_class.fetch(:nope) }.to(raise_error(described_class::UnknownPluginError, /nope/))
  end

  it "iterates over plugin instances" do
    described_class.register(:a, PluginRegistrySpecPluginA)
    described_class.register(:b, PluginRegistrySpecPluginB)
    classes = described_class.each_plugin.to_a.map(&:class)
    expect(classes).to(contain_exactly(PluginRegistrySpecPluginA, PluginRegistrySpecPluginB))
  end

  it "writes plugin_name onto the registered class" do
    described_class.register(:custom_a, PluginRegistrySpecPluginA)
    expect(PluginRegistrySpecPluginA.plugin_name).to(eq(:custom_a))
    expect(PluginRegistrySpecPluginA.new.name).to(eq(:custom_a))
  end

  it "uses the registry name (not the class name) for cli_namespace" do
    described_class.register(:a_b_c, PluginRegistrySpecPluginA)
    expect(PluginRegistrySpecPluginA.cli_namespace).to(eq("a-b-c"))
  end

  it "tolerates a plain object that doesn't expose plugin_name=" do
    bare = Object.new
    described_class.register(:bare, bare)
    expect(described_class.fetch_class(:bare)).to(equal(bare))
  end
end
