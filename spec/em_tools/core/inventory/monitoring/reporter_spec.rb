# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Inventory::Monitoring::Reporter) do
  let(:client) { instance_double(EmTools::Core::Monitoring::Client, configured?: true) }
  let(:reporter) { described_class.new(client: client) }

  it "reports done runs with counters" do
    expect(client).to(receive(:post_inventory_sync_run).with(
      hash_including(
        source: "AMZ_DE",
        status: "done",
        docs_indexed: 42,
        docs_deleted: 3,
        run_on: Date.today.iso8601,
      ),
    ))

    reporter.report_done(
      source: "AMZ_DE",
      gs_uri: "gs://em-bucket/AMZ_DE-Inv.csv",
      docs_indexed: 42,
      docs_deleted: 3,
      duration_ms: 1200,
      meta: { index: "em_inventory" },
    )
  end

  it "skips posting when the client is not configured" do
    silent_client = instance_double(EmTools::Core::Monitoring::Client, configured?: false)
    silent = described_class.new(client: silent_client)

    expect(silent_client).not_to(receive(:post_inventory_sync_run))
    silent.report_running(source: "AMZ_DE")
  end
end
