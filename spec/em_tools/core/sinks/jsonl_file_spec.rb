# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Sinks::JsonlFile) do
  it "writes records as JSONL" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "feed.ndjson")
      sink = described_class.new(path: path)

      sink.index("asin" => "B000000001")
      sink.close

      expect(File.readlines(path, chomp: true).map { |line| JSON.parse(line) }).to(eq([
        { "asin" => "B000000001" },
      ]))
      expect(sink.stats).to(eq(file_written: 1))
    end
  end
end
