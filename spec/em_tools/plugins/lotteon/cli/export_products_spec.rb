# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Lotteon::Cli::ExportProducts) do
  it "exports to the requested file path" do
    exporter = instance_double(EmTools::Plugins::Lotteon::Exporters::ProductsExporter)
    allow(EmTools::Plugins::Lotteon::Exporters::ProductsExporter).to(receive(:new).and_return(exporter))
    allow(exporter).to(receive(:to_jsonl))

    described_class.new.call(output: "tmp/lotteon.ndjson", batch_size: "50")

    expect(exporter).to(have_received(:to_jsonl).with("tmp/lotteon.ndjson", batch_size: 50))
  end
end
