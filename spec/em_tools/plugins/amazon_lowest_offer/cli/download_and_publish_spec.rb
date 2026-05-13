# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::AmazonLowestOffer::Cli::DownloadAndPublish) do
  it "runs the composite pipeline" do
    pipeline = instance_double(EmTools::Plugins::AmazonLowestOffer::Pipelines::DownloadAndPublish)
    allow(EmTools::Plugins::AmazonLowestOffer::Pipelines::DownloadAndPublish).to receive(:new).and_return(pipeline)
    allow(pipeline).to receive(:run!).and_return(EmTools::Core::Cli::Runner::Result.new(summary: "ok"))
    allow(EmTools::Core::Cli::Runner).to receive(:run).and_yield

    described_class.new.run([])

    expect(EmTools::Plugins::AmazonLowestOffer::Pipelines::DownloadAndPublish).to(have_received(:new))
  end
end
