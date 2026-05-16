# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Amazon::LowestOffer::Pipelines::DownloadAndPublish) do
  it "calls SeedFiles.sync_from_env! then PublishSnapshot#run! and stitches the summary" do
    seed_calls = []
    allow(EmTools::Plugins::Amazon::LowestOffer::Sources::SeedFiles).to(receive(:sync_from_env!)) do |**kw|
      seed_calls << kw
    end
    snapshot_result = EmTools::Core::Cli::Runner::Result.new(summary: "Coverage published us=42 (...)")
    snapshot = instance_double(
      EmTools::Plugins::Amazon::LowestOffer::Pipelines::PublishSnapshot,
      run!: snapshot_result,
    )

    result = described_class.new(
      target_dir: "/tmp/test-seeds", env: { "GCS_BUCKET" => "x" }, snapshot: snapshot,
    ).run!

    expect(seed_calls).to(eq([{ target_dir: "/tmp/test-seeds", env: { "GCS_BUCKET" => "x" } }]))
    expect(result).to(be_a(EmTools::Core::Cli::Runner::Result))
    expect(result.summary).to(eq("Seeds synced to /tmp/test-seeds; Coverage published us=42 (...)"))
  end

  it "defaults target_dir to ./tmp when unset" do
    allow(EmTools::Plugins::Amazon::LowestOffer::Sources::SeedFiles).to(receive(:sync_from_env!))
    snapshot = instance_double(
      EmTools::Plugins::Amazon::LowestOffer::Pipelines::PublishSnapshot,
      run!: EmTools::Core::Cli::Runner::Result.new(summary: ""),
    )

    pipeline = described_class.new(snapshot: snapshot)
    pipeline.run!

    expect(EmTools::Plugins::Amazon::LowestOffer::Sources::SeedFiles).to(have_received(:sync_from_env!)
      .with(target_dir: File.join(Dir.pwd, "tmp"), env: ENV))
  end
end
