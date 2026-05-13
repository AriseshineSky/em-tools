# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Ssg::Cli::ExportProducts) do
  it "exports to the requested file path" do
    exporter = instance_double(EmTools::Plugins::Ssg::Exporters::ProductsExporter)
    allow(EmTools::Plugins::Ssg::Exporters::ProductsExporter).to receive(:new).and_return(exporter)
    allow(exporter).to receive(:to_jsonl)

    described_class.new.run(["-o", "tmp/ssg.ndjson", "-b", "42"])

    expect(exporter).to(have_received(:to_jsonl).with("tmp/ssg.ndjson", batch_size: 42))
  end
end
