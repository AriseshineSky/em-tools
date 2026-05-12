# frozen_string_literal: true

require "spec_helper"
require "csv"

RSpec.describe(EmTools::Core::ProductFormatting::UploadedProductIds) do
  let(:client) { instance_double(EmTools::Clients::SpreeClient, endpoint: "https://store.example.com", api_key: "k") }

  before { EmTools::Core::Logger.silent! }

  it "downloads the inventory CSV, parses SourceProductID, and returns a deduped Set" do
    rows = [
      ["SourceProductID", "Other"],
      ["B0001ABCD", "x"],
      ["", "skip-blank"],
      ["B0002EFGH", "y"],
      ["B0001ABCD", "z"], # duplicate
    ]
    captured_path = nil
    allow(client).to(receive(:download_inventory)) do |source, path|
      expect(source).to(eq("AMZ_US"))
      captured_path = path
      File.write(path, rows.map { |r| r.join(",") }.join("\n"))
    end

    result = described_class.new(client: client).fetch("AMZ_US")

    expect(result).to(be_a(Set))
    expect(result.to_a.sort).to(eq(["B0001ABCD", "B0002EFGH"]))
    expect(File.exist?(captured_path)).to(be(false)) # Tempfile auto-cleanup
  end

  it "returns an empty Set when the client never writes the file" do
    allow(client).to(receive(:download_inventory)) # no-op (path missing afterwards)

    expect(described_class.new(client: client).fetch("AMZ_US")).to(eq(Set.new))
  end

  it "skips work and warns when client is missing endpoint or api key" do
    bare = instance_double(EmTools::Clients::SpreeClient, endpoint: "", api_key: "")

    expect(described_class.new(client: bare).fetch("AMZ_US")).to(eq(Set.new))
  end

  it "skips work when client is nil (Python parity: empty endpoint/key path)" do
    expect(described_class.new(client: nil).fetch("AMZ_US")).to(eq(Set.new))
  end

  it "tolerates malformed UTF-8 bytes in the CSV (Python uses errors=ignore)" do
    allow(client).to(receive(:download_inventory)) do |_source, path|
      # \xFF is invalid UTF-8; we expect :replace to swallow it.
      File.binwrite(path, "SourceProductID,Other\nB0001\xFFABCD,x\n")
    end

    result = described_class.new(client: client).fetch("AMZ_US")
    expect(result.size).to(eq(1))
    expect(result.first).to(start_with("B0001"))
  end

  describe ".from_env" do
    it "returns nil when SPREE_ENDPOINT or SPREE_API_KEY is missing" do
      expect(described_class.from_env(env: {})).to(be_nil)
      expect(described_class.from_env(env: { "SPREE_ENDPOINT" => "x" })).to(be_nil)
      expect(described_class.from_env(env: { "SPREE_API_KEY" => "x" })).to(be_nil)
    end

    it "constructs a client when both env vars are present" do
      env = { "SPREE_ENDPOINT" => "https://store.example.com", "SPREE_API_KEY" => "secret" }
      loader = described_class.from_env(env: env)
      expect(loader).to(be_a(described_class))
    end
  end
end
