# frozen_string_literal: true

require "spec_helper"
require "net/http"

RSpec.describe(EmTools::Core::Blacklist::Loader) do
  let(:http) { instance_double(Net::HTTP) }
  let(:loader) { described_class.new(endpoint: "https://api.example.com", path: "/v1/blacklist", token: "tok") }
  let(:stub_response_class) { Struct.new(:code, :body, :message, keyword_init: true) }

  before do
    EmTools::Core::Logger.silent!
    allow(Net::HTTP).to(receive(:new).and_return(http))
    allow(http).to(receive(:use_ssl=))
    allow(http).to(receive(:open_timeout=))
    allow(http).to(receive(:read_timeout=))
  end

  def stub_response(code:, body:, message: "OK")
    res = stub_response_class.new(code: code.to_s, body: body, message: message)
    allow(http).to(receive(:request).and_return(res))
  end

  def stub_responses(*bodies)
    queue = bodies.map { |b| stub_response_class.new(code: "200", body: b, message: "OK") }
    allow(http).to(receive(:request)) { queue.shift || raise("ran out of stubbed responses") }
  end

  describe "#fetch" do
    it "raises ConfigurationError when endpoint or token is missing" do
      bad = described_class.new(endpoint: nil, path: "/v1/blacklist", token: "tok")
      expect { bad.fetch }.to(raise_error(EmTools::Core::Errors::ConfigurationError, /BLACKLIST_API_ENDPOINT/))

      bad = described_class.new(endpoint: "https://api.example.com", path: "/v1/blacklist", token: " ")
      expect { bad.fetch }.to(raise_error(EmTools::Core::Errors::ConfigurationError, /BLACKLIST_API_TOKEN/))
    end

    it "raises ConfigurationError when endpoint is not http(s)" do
      bad = described_class.new(endpoint: "ftp://example.com", path: "/x", token: "tok")
      expect { bad.fetch }.to(raise_error(EmTools::Core::Errors::ConfigurationError, /must be an http\(s\) URL/))
    end

    it "raises ConfigurationError on non-2xx responses" do
      stub_response(code: 401, body: "nope", message: "Unauthorized")
      expect { loader.fetch }.to(raise_error(EmTools::Core::Errors::ConfigurationError, /HTTP 401 Unauthorized/))
    end

    it "raises ConfigurationError on non-JSON body" do
      stub_response(code: 200, body: "<html>oops</html>")
      expect { loader.fetch }.to(raise_error(EmTools::Core::Errors::ConfigurationError, /non-JSON body/))
    end

    it "sends an Authorization bearer header and a token query string" do
      captured = nil
      allow(http).to(receive(:request)) do |req|
        captured = req
        stub_response_class.new(code: "200", body: "{}", message: "OK")
      end

      loader.fetch

      expect(captured["Authorization"]).to(eq("Bearer tok"))
      expect(captured["Accept"]).to(eq("application/json"))
      expect(captured.path).to(include("token=tok"))
    end
  end

  describe "#each_page (pagination)" do
    it "follows next_cursor and stops when has_more is false" do
      captured_paths = []
      queue = [
        '{"blacklist_keywords":[{"keywords":"a"}],"has_more":true,"next_cursor":100}',
        '{"blacklist_keywords":[{"keywords":"b"}],"has_more":true,"next_cursor":200}',
        '{"blacklist_keywords":[{"keywords":"c"}],"has_more":false,"next_cursor":null}',
      ].map { |b| stub_response_class.new(code: "200", body: b, message: "OK") }
      allow(http).to(receive(:request)) do |req|
        captured_paths << req.path
        queue.shift
      end

      pages = loader.fetch_pages

      expect(pages.size).to(eq(3))
      expect(captured_paths[0]).to(include("token=tok"))
      expect(captured_paths[0]).not_to(include("cursor="))
      expect(captured_paths[1]).to(include("cursor=100"))
      expect(captured_paths[2]).to(include("cursor=200"))
    end

    it "stops if next_cursor does not advance (defensive guard)" do
      stub_responses(
        '{"blacklist_keywords":[{"keywords":"a"}],"has_more":true,"next_cursor":42}',
        '{"blacklist_keywords":[{"keywords":"b"}],"has_more":true,"next_cursor":42}',
      )

      pages = loader.fetch_pages

      expect(pages.size).to(eq(2))
    end

    it "honours the max_pages safety ceiling" do
      bounded = described_class.new(
        endpoint: "https://api.example.com",
        path: "/v1/blacklist",
        token: "tok",
        max_pages: 2,
      )
      stub_responses(
        '{"blacklist_keywords":[{"keywords":"a"}],"has_more":true,"next_cursor":1}',
        '{"blacklist_keywords":[{"keywords":"b"}],"has_more":true,"next_cursor":2}',
        '{"blacklist_keywords":[{"keywords":"c"}],"has_more":true,"next_cursor":3}',
      )

      expect(bounded.fetch_pages.size).to(eq(2))
    end
  end

  describe "#fetch_keywords" do
    it "extracts keywords across paginated responses and dedupes" do
      stub_responses(
        '{"blacklist_keywords":[{"keywords":"a"},{"keywords":"b"}],"has_more":true,"next_cursor":1}',
        '{"blacklist_keywords":[{"keywords":"b"},{"keywords":" c "}],"has_more":false}',
      )

      expect(loader.fetch_keywords).to(eq(["a", "b", "c"]))
    end

    it "extracts the legacy {keywords:[array]} shape" do
      stub_response(code: 200, body: <<~JSON)
        {"blacklist_keywords":[
          {"keywords":["a","b"]},
          {"keywords":"c"},
          {"keywords":[" d ", "", null]}
        ],"has_more":false}
      JSON
      expect(loader.fetch_keywords).to(eq(["a", "b", "c", "d"]))
    end

    it "extracts a flat {keywords:[...]} shape" do
      stub_response(code: 200, body: '{"keywords":["x","y","x"]}')
      expect(loader.fetch_keywords).to(eq(["x", "y"]))
    end

    it "extracts a bare array body" do
      stub_response(code: 200, body: '["foo","bar"]')
      expect(loader.fetch_keywords).to(eq(["foo", "bar"]))
    end

    it "returns [] for unknown shape rather than raising" do
      stub_response(code: 200, body: '{"unrelated":42}')
      expect(loader.fetch_keywords).to(eq([]))
    end
  end
end
