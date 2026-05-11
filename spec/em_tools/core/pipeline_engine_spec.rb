# frozen_string_literal: true

require "spec_helper"

class PipelineEngineSpecEvenFilter
  def call(record)
    record.even?
  end
end

class PipelineEngineSpecDoubleTransform
  def call(record)
    record * 2
  end
end

class PipelineEngineSpecArraySink
  attr_reader :items, :flushed

  def initialize
    @items = []
    @flushed = false
  end

  def index(record)
    @items << record
  end

  def flush!
    @flushed = true
  end
end

class PipelineEngineSpecPlugin < EmTools::Core::Plugin::Base
  attr_accessor :external_source, :external_sink

  def filters
    [PipelineEngineSpecEvenFilter]
  end

  def transforms
    [PipelineEngineSpecDoubleTransform]
  end

  def source(**_opts)
    @external_source
  end

  def sink(**_opts)
    @external_sink
  end
end

RSpec.describe(EmTools::Core::PipelineEngine) do
  let(:plugin) { PipelineEngineSpecPlugin.new }
  let(:sink) { PipelineEngineSpecArraySink.new }

  describe "#call" do
    it "returns nil and skips the sink when filters reject the record" do
      engine = described_class.new(plugin, source: [], sink: sink)
      expect(engine.call(1)).to(be_nil)
      expect(sink.items).to(be_empty)
    end

    it "transforms and writes accepted records" do
      engine = described_class.new(plugin, source: [], sink: sink)
      expect(engine.call(4)).to(eq(8))
      expect(sink.items).to(eq([8]))
    end
  end

  describe "#run" do
    it "iterates source, applies the chain, and flushes the sink" do
      engine = described_class.new(plugin, source: [1, 2, 3, 4, 5, 6], sink: sink)
      engine.run
      expect(sink.items).to(eq([4, 8, 12]))
      expect(sink.flushed).to(be(true))
    end

    it "accepts source / sink supplied via plugin instance" do
      plugin.external_source = [2, 3]
      plugin.external_sink = sink
      engine = described_class.new(plugin)
      engine.run
      expect(sink.items).to(eq([4]))
    end
  end
end
