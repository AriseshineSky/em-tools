# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Oliveyoung::Cli::BuildStoreUpload) do
  let(:exporter) { instance_double(EmTools::Plugins::Oliveyoung::Exporters::ProductsExporter) }
  let(:plugin) { instance_double(EmTools::Plugins::Oliveyoung::Plugin) }

  before do
    allow(EmTools::Core::PluginRegistry).to(receive(:fetch).with(:oliveyoung).and_return(plugin))
    allow(plugin).to(receive(:products_exporter).and_return(exporter))
    allow(exporter).to(receive_messages(
      to_jsonl: { total: 0, written: 0, blocked: 0, filtered: 0 },
      write_jsonl: { total: 0, written: 0, blocked: 0, filtered: 0 },
    ))
  end

  it "always enables upload formatting on the exporter" do
    described_class.new.call(output: "tmp/oy_up.ndjson", batch_size: "10")

    expect(plugin).to(have_received(:products_exporter).with(
      hash_including(for_upload: true, validate_for_upload: true),
    ))
    expect(exporter).to(have_received(:to_jsonl).with("tmp/oy_up.ndjson", batch_size: 10))
  end

  it "defaults output to tmp/oliveyoung_store_upload.ndjson when -o is omitted" do
    described_class.new.call(batch_size: "5")

    expect(exporter).to(have_received(:to_jsonl).with(
      EmTools::Plugins::Oliveyoung::Cli::BuildStoreUpload::DEFAULT_OUTPUT,
      batch_size: 5,
    ))
  end

  it "passes inventory and validation flags through" do
    described_class.new.call(
      output: "out.ndjson",
      inventory_source: "OY",
      no_validate_for_upload: true,
      batch_size: "1",
    )

    expect(plugin).to(have_received(:products_exporter).with(
      hash_including(inventory_source: "OY", validate_for_upload: false),
    ))
  end
end
