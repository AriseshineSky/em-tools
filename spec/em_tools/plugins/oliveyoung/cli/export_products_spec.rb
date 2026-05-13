# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Oliveyoung::Cli::ExportProducts) do
  let(:exporter) { instance_double(EmTools::Plugins::Oliveyoung::Exporters::ProductsExporter) }
  let(:plugin) { instance_double(EmTools::Plugins::Oliveyoung::Plugin) }

  before do
    allow(EmTools::Core::PluginRegistry).to(receive(:fetch).with(:oliveyoung).and_return(plugin))
    allow(plugin).to(receive(:products_exporter).and_return(exporter))
    allow(exporter).to(receive(:to_jsonl))
    allow(exporter).to(receive(:write_jsonl))
  end

  it "exports to a file path with the default source filter" do
    described_class.new.call(output: "tmp/oliveyoung.ndjson", batch_size: "42")

    expect(plugin).to(have_received(:products_exporter).with(source_value: nil))
    expect(exporter).to(have_received(:to_jsonl).with("tmp/oliveyoung.ndjson", batch_size: 42))
  end

  it "passes --source through to the plugin factory" do
    described_class.new.call(source: "OLIVEYOUNG", batch_size: "10")

    expect(plugin).to(have_received(:products_exporter).with(source_value: "OLIVEYOUNG"))
    expect(exporter).to(have_received(:write_jsonl).with($stdout, batch_size: 10))
  end
end
