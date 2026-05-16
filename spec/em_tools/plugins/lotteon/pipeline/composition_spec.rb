# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Lotteon::Pipeline) do
  describe(EmTools::Plugins::Lotteon::Pipeline::ExclusionChain) do
    let(:loose) { EmTools::Plugins::Lotteon::Exclusions::MinTitleLength.new(min: 1, title_field: "title") }
    let(:strict) { EmTools::Plugins::Lotteon::Exclusions::MinTitleLength.new(min: 10, title_field: "title") }

    it "ORs blocked? across policies" do
      chain = described_class.new([loose, strict])
      expect(chain.blocked?("title" => "short")).to(be(true))
    end

    it "delegates matched to the first blocking policy" do
      chain = described_class.new([loose, strict])
      expect(chain.matched("title" => "short")).to(eq(["min_title_length"]))
    end
  end

  describe(EmTools::Plugins::Lotteon::Pipeline::TransformChain) do
    it "threads call through steps and honors :skip" do
      steps = [
        ->(h) { h.merge("a" => 1) },
        ->(h) { h["a"] == 1 ? :skip : h },
        ->(h) { h.merge("b" => 2) },
      ]
      chain = described_class.new(steps)
      skip = EmTools::Plugins::Lotteon::Formatting::ProductExportFormatter::SKIP
      expect(chain.call({ "x" => true })).to(eq(skip))
    end
  end

  describe(EmTools::Plugins::Lotteon::Pipeline::Registry) do
    describe ".build_exclusions" do
      it "builds min_title_length entries" do
        list = described_class.build_exclusions(
          [{ "type" => "min_title_length", "min" => 5 }],
          keyword_policy_factory: ->(_) { raise "unused" },
        )
        expect(list.size).to(eq(1))
        expect(list.first).to(be_a(EmTools::Plugins::Lotteon::Exclusions::MinTitleLength))
        expect(list.first.blocked?("title" => "abcd")).to(be(true))
      end

      it "delegates keyword_blacklist to the factory" do
        fake = Object.new
        factory = ->(entry) { fake if entry["type"] == "keyword_blacklist" }
        list = described_class.build_exclusions([{ "type" => "keyword_blacklist" }], keyword_policy_factory: factory)
        expect(list).to(eq([fake]))
      end
    end
  end

  describe(EmTools::Plugins::Lotteon::Plugin) do
    describe "#partition_transform_pipeline_entries" do
      it "places lotteon_upload_format in the format bucket and preserves refine order" do
        plugin = EmTools::Plugins::Lotteon::Plugin.allocate
        fmt, ref = plugin.send(
          :partition_transform_pipeline_entries,
          [
            { "type" => "custom_refinement" },
            { "type" => "lotteon_upload_format", "validate" => true },
            { "type" => "another_refinement" },
          ],
        )
        expect(fmt.map { |h| h["type"] }).to(eq(["lotteon_upload_format"]))
        expect(ref.map { |h| h["type"] }).to(eq(["custom_refinement", "another_refinement"]))
      end
    end
  end

  describe(EmTools::Plugins::Lotteon::Exclusions::MinTitleLength) do
    it "blocks short titles" do
      rule = described_class.new(min: 3, title_field: "title")
      expect(rule.blocked?("title" => "ab")).to(be(true))
      expect(rule.matched("title" => "ab")).to(eq(["min_title_length"]))
      expect(rule.blocked?("title" => "abc")).to(be(false))
      expect(rule.matched("title" => "abc")).to(eq([]))
    end
  end
end
