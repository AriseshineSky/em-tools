# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::AmazonLowestOffer::Cli::PublishSnapshot) do
  it "passes marketplace arguments to the pipeline" do
    pipeline = instance_double(EmTools::Plugins::AmazonLowestOffer::Pipelines::PublishSnapshot)
    allow(EmTools::Plugins::AmazonLowestOffer::Pipelines::PublishSnapshot).to(receive(:new).and_return(pipeline))
    allow(pipeline).to(receive(:run!).and_return(EmTools::Core::Cli::Runner::Result.new(summary: "ok")))
    allow(EmTools::Core::Cli::Runner).to(receive(:run).and_yield)

    described_class.new.call(marketplaces: ["US,CA"])

    expect(EmTools::Plugins::AmazonLowestOffer::Pipelines::PublishSnapshot)
      .to(have_received(:new).with(hash_including(cli_marketplaces: "us,ca")))
  end
end
