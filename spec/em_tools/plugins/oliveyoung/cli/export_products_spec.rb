# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Oliveyoung::Cli::ExportProducts) do
  let(:exporter) { instance_double(EmTools::Plugins::Oliveyoung::Exporters::ProductsExporter) }
  let(:plugin) { instance_double(EmTools::Plugins::Oliveyoung::Plugin) }

  before do
    allow(EmTools::Core::PluginRegistry).to(receive(:fetch).with(:oliveyoung).and_return(plugin))
    allow(plugin).to(receive(:products_exporter).and_return(exporter))
    allow(exporter).to(receive_messages(to_jsonl: { total: 0, written: 0, blocked: 0 }, write_jsonl: { total: 0, written: 0, blocked: 0 }))
  end

  it "wires keyword filter ON by default and writes to the requested file" do
    described_class.new.call(output: "tmp/oy.ndjson", batch_size: "42")

    expect(plugin).to(have_received(:products_exporter).with(
      hash_including(
        source_value: nil,
        apply_keyword_policy: true,
        keywords: nil,
        blocked_output_path: "tmp/oy.blocked.ndjson",
        title_field: "title",
        brand_field: "brand",
      ),
    ))
    expect(exporter).to(have_received(:to_jsonl).with("tmp/oy.ndjson", batch_size: 42))
  end

  it "supports --no-keyword-filter and skips the side-file" do
    described_class.new.call(keyword_filter: false, batch_size: "10")

    expect(plugin).to(have_received(:products_exporter).with(
      hash_including(apply_keyword_policy: false, blocked_output_path: nil),
    ))
    expect(exporter).to(have_received(:write_jsonl).with($stdout, batch_size: 10))
  end

  it "loads keywords from --keywords-path instead of the admin API" do
    Dir.mktmpdir do |dir|
      kw_path = File.join(dir, "kw.txt")
      File.write(kw_path, "weed\nlsd\n")

      described_class.new.call(keywords_path: kw_path, batch_size: "10")

      expect(plugin).to(have_received(:products_exporter).with(
        hash_including(apply_keyword_policy: true, keywords: ["weed", "lsd"]),
      ))
    end
  end

  it "passes --source through to the plugin factory" do
    described_class.new.call(source: "OLIVEYOUNG", batch_size: "10")

    expect(plugin).to(have_received(:products_exporter).with(hash_including(source_value: "OLIVEYOUNG")))
  end
end
