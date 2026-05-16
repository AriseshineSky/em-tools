# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Lotteon::Cli::BuildUploadPayload) do
  let(:exporter) { instance_double(EmTools::Plugins::Lotteon::Exporters::ProductsExporter) }
  let(:plugin) { instance_double(EmTools::Plugins::Lotteon::Plugin) }

  before do
    allow(EmTools::Core::PluginRegistry).to(receive(:fetch).with(:lotteon).and_return(plugin))
    allow(plugin).to(receive(:products_exporter).and_return(exporter))
    allow(exporter).to(receive(:to_jsonl).and_return({ total: 0, written: 0, blocked: 0, filtered: 0 }))
  end

  it "requests upload payload wiring and writes the default output path" do
    described_class.new.call(batch_size: "5")

    expect(plugin).to(have_received(:products_exporter).with(
      hash_including(
        upload_payload: true,
        apply_keyword_policy: true,
        validate_payload: true,
        inventory_source: "lotteon",
      ),
    ))
    expect(exporter).to(have_received(:to_jsonl).with(
      EmTools::Plugins::Lotteon::Cli::BuildUploadPayload::DEFAULT_OUTPUT,
      batch_size: 5,
    ))
  end

  it "passes --no-validate-payload through" do
    described_class.new.call(no_validate_payload: true, batch_size: "1")

    expect(plugin).to(have_received(:products_exporter).with(hash_including(validate_payload: false)))
  end
end
