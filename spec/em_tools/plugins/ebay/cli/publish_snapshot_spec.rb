# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Ebay::Cli::PublishSnapshot) do
  it "passes the marketplace argument to the pipeline" do
    pipeline = instance_double(EmTools::Plugins::Ebay::Pipelines::PublishSnapshot)
    allow(EmTools::Plugins::Ebay::Pipelines::PublishSnapshot).to receive(:new).and_return(pipeline)
    allow(pipeline).to receive(:run!).and_return(EmTools::Core::Cli::Runner::Result.new(summary: "ok"))
    allow(EmTools::Core::Cli::Runner).to receive(:run).and_yield

    described_class.new.run(["us"])

    expect(EmTools::Plugins::Ebay::Pipelines::PublishSnapshot).to(have_received(:new).with(cli_marketplace: "us"))
  end
end
