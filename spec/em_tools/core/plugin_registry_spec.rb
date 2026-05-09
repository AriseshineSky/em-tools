# frozen_string_literal: true

require 'spec_helper'

class PluginRegistrySpecPluginA < EmTools::Core::Plugin::Base
  def filters
    %w[A]
  end
end

class PluginRegistrySpecPluginB < EmTools::Core::Plugin::Base; end

RSpec.describe EmTools::Core::PluginRegistry do
  before do
    @snapshot = described_class.names.to_h { |n| [n, described_class.fetch_class(n)] }
    described_class.reset!
  end

  after do
    described_class.reset!
    @snapshot.each { |name, klass| described_class.register(name, klass) }
  end

  it 'registers and fetches a plugin by name' do
    described_class.register(:a, PluginRegistrySpecPluginA)
    plugin = described_class.fetch(:a)
    expect(plugin).to be_a(PluginRegistrySpecPluginA)
    expect(plugin.filters).to eq(%w[A])
  end

  it 'lists registered names' do
    described_class.register(:a, PluginRegistrySpecPluginA)
    described_class.register(:b, PluginRegistrySpecPluginB)
    expect(described_class.names).to contain_exactly(:a, :b)
  end

  it 'raises on unknown plugin' do
    expect { described_class.fetch(:nope) }.to raise_error(described_class::UnknownPluginError, /nope/)
  end

  it 'iterates over plugin instances' do
    described_class.register(:a, PluginRegistrySpecPluginA)
    described_class.register(:b, PluginRegistrySpecPluginB)
    classes = described_class.each_plugin.to_a.map(&:class)
    expect(classes).to contain_exactly(PluginRegistrySpecPluginA, PluginRegistrySpecPluginB)
  end
end
