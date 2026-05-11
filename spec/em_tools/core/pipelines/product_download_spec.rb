# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Pipelines::ProductDownload) do
  let(:dumper) { instance_double(EmTools::Core::Sinks::IndexDumper, run!: :ok) }

  before { EmTools::Core::Logger.silent! }

  describe "#run!" do
    it "wires the IndexDumper from env, requesting the data cluster and no extras when filter is off" do
      env = { "ES_DUMP_INDEX" => "user1_kr_products" }
      expect(EmTools::Core::Sinks::IndexDumper).to(receive(:from_env)
        .with(env: env, prefer_data_cluster: true).and_return(dumper))

      expect(described_class.new(blacklist_filter: false, env: env).run!).to(eq(:ok))
    end

    it "loads keywords, builds a blacklist policy, and forwards policy + paths when blacklist is on" do
      env = { "ES_DUMP_INDEX" => "user1_kr_products", "ES_DUMP_OUTPUT" => "tmp/out.ndjson" }
      loader = instance_double(EmTools::Core::Blacklist::Loader, fetch_keywords: ["foo", "bar"])
      allow(EmTools::Core::Blacklist::Loader).to(receive(:new).and_return(loader))

      captured = {}
      allow(EmTools::Core::Sinks::IndexDumper).to(receive(:from_env)) do |**kwargs|
        captured = kwargs
        dumper
      end

      described_class.new(env: env).run!

      expect(captured[:env]).to(eq(env))
      expect(captured[:prefer_data_cluster]).to(be(true))
      expect(captured[:policy]).to(be_a(EmTools::Core::Blacklist::Strategy::TitleBrand))
      expect(captured[:policy].keyword_count).to(eq(2))
      expect(captured[:blocked_output_path]).to(eq("tmp/out.blocked.ndjson"))
    end

    it "falls back to tmp/<index>.blocked.ndjson when ES_DUMP_OUTPUT is unset" do
      env = { "ES_DUMP_INDEX" => "user1_kr_products" }
      allow(EmTools::Core::Blacklist::Loader).to(receive(:new)
        .and_return(instance_double(EmTools::Core::Blacklist::Loader, fetch_keywords: [])))
      allow(EmTools::Core::Sinks::IndexDumper).to(receive(:from_env).and_return(dumper))

      described_class.new(env: env).run!

      expect(EmTools::Core::Sinks::IndexDumper).to(have_received(:from_env)
        .with(hash_including(blocked_output_path: "tmp/user1_kr_products.blocked.ndjson")))
    end

    it "honours an explicit blocked_output_path override" do
      env = { "ES_DUMP_INDEX" => "x", "ES_DUMP_OUTPUT" => "tmp/out.ndjson" }
      allow(EmTools::Core::Blacklist::Loader).to(receive(:new)
        .and_return(instance_double(EmTools::Core::Blacklist::Loader, fetch_keywords: [])))
      allow(EmTools::Core::Sinks::IndexDumper).to(receive(:from_env).and_return(dumper))

      described_class.new(env: env, blocked_output_path: "/custom/path.ndjson").run!

      expect(EmTools::Core::Sinks::IndexDumper).to(have_received(:from_env)
        .with(hash_including(blocked_output_path: "/custom/path.ndjson")))
    end

    it "passes custom title_field / brand_field through to the policy" do
      env = { "ES_DUMP_INDEX" => "x" }
      allow(EmTools::Core::Blacklist::Loader).to(receive(:new)
        .and_return(instance_double(EmTools::Core::Blacklist::Loader, fetch_keywords: ["bonafide"])))
      captured_policy = nil
      allow(EmTools::Core::Sinks::IndexDumper).to(receive(:from_env)) do |**kwargs|
        captured_policy = kwargs[:policy]
        dumper
      end

      described_class.new(env: env, title_field: "title_en", brand_field: "manufacturer").run!

      expect(captured_policy.text_for("title_en" => "Bonafide", "manufacturer" => "X")).to(eq("bonafide x"))
    end
  end
end
