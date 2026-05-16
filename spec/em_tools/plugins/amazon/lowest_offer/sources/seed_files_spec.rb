# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Amazon::LowestOffer::Sources::SeedFiles) do
  describe ".sync_from_env!" do
    it "lifts creds + GCS env defaults + canonical marketplace list into sync_from_gcs" do
      env = { "GCS_BUCKET" => "custom-bucket", "GCS_SEEDS_PREFIX" => "custom/prefix/" }
      allow(EmTools::Clients::GcsServiceAccountPath).to(receive(:require!).and_return("/creds.json"))
      captured = nil
      allow(described_class).to(receive(:sync_from_gcs)) { |dir, **kwargs| captured = kwargs.merge(dir: dir) }

      result = described_class.sync_from_env!(target_dir: "/tmp/seeds", env: env)

      expect(result).to(eq("/tmp/seeds"))
      expect(captured).to(include(
        dir: "/tmp/seeds",
        creds_path: "/creds.json",
        bucket: "custom-bucket",
        prefix: "custom/prefix/",
        force: true,
      ))
      expect(captured[:marketplaces]).to(eq(
        EmTools::Plugins::Amazon::LowestOffer::Queries::ListingsCoverageQuery::DEFAULT_MARKETPLACES,
      ))
    end

    it "falls back to default bucket / prefix when env keys are missing" do
      allow(EmTools::Clients::GcsServiceAccountPath).to(receive(:require!).and_return("/creds.json"))
      captured = nil
      allow(described_class).to(receive(:sync_from_gcs)) { |_dir, **kwargs| captured = kwargs }

      described_class.sync_from_env!(target_dir: "/tmp/seeds", env: {})

      expect(captured).to(include(bucket: "em-bucket", prefix: "em-analytics"))
    end

    it "honors a caller-supplied marketplace override" do
      allow(EmTools::Clients::GcsServiceAccountPath).to(receive(:require!).and_return("/c.json"))
      captured = nil
      allow(described_class).to(receive(:sync_from_gcs)) { |_dir, **kwargs| captured = kwargs }

      described_class.sync_from_env!(target_dir: "/x", env: {}, marketplaces: ["us"])
      expect(captured[:marketplaces]).to(eq(["us"]))
    end
  end
end
