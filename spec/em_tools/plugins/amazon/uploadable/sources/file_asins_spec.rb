# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Amazon::Uploadable::Sources::FileAsins) do
  it "streams normalized valid ASINs from a local file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "asins.txt")
      File.write(path, "b000000001\ninvalid\n  123456789X  \n")

      expect(described_class.new(path: path).to_a).to(eq(["B000000001", "123456789X"]))
    end
  end

  it "honors max_asins" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "asins.txt")
      File.write(path, "B000000001\nB000000002\n")

      expect(described_class.new(path: path, max_asins: 1).to_a).to(eq(["B000000001"]))
    end
  end
end
