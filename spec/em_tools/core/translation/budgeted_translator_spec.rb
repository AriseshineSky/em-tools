# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

module EmToolsBudgetedTranslatorSpec
  TranslationResult = Struct.new(:text, :origin, :to, :from, keyword_init: true)
end

RSpec.describe(EmTools::Core::Translation::BudgetedTranslator) do
  let(:fake_client) do
    Class.new do
      attr_reader :batches

      def initialize
        @batches = []
      end

      def translate(*texts, to:, from: nil, format: nil, model: nil, cid: nil)
        @batches << { texts: texts.flatten, to: to, from: from, format: format, model: model }
        texts.flatten.map { |t| EmToolsBudgetedTranslatorSpec::TranslationResult.new(text: "[#{to}]#{t}", origin: t, to: to, from: from) }
      end
    end.new
  end

  it "raises TranslationDisabledError when max_billable_chars is not positive" do
    expect do
      described_class.new(max_billable_chars: 0, v2_client: fake_client)
    end.to(raise_error(EmTools::Core::Errors::TranslationDisabledError))
  end

  it "translates uncached text and bills source characters" do
    t = described_class.new(max_billable_chars: 100, v2_client: fake_client, min_interval_between_calls: 0)
    out = t.translate("abc", from: "en", to: "ko")
    expect(out).to(eq("[ko]abc"))
    expect(t.chars_billed_this_session).to(eq(3))
    expect(t.api_calls).to(eq(1))
  end

  it "does not bill cache hits" do
    Dir.mktmpdir do |dir|
      t = described_class.new(
        max_billable_chars: 10,
        cache_dir: dir,
        v2_client: fake_client,
        min_interval_between_calls: 0,
      )
      t.translate("x", from: "en", to: "ko")
      t.translate("x", from: "en", to: "ko")
      expect(t.chars_billed_this_session).to(eq(1))
      expect(t.api_calls).to(eq(1))
    end
  end

  it "raises TranslationBudgetExceededError when session cap would be exceeded" do
    t = described_class.new(max_billable_chars: 2, v2_client: fake_client, min_interval_between_calls: 0)
    expect { t.translate("abc", from: "en", to: "ko") }.to(raise_error(EmTools::Core::Errors::TranslationBudgetExceededError))
  end

  it "enforces daily cap using state file" do
    Dir.mktmpdir do |dir|
      state = File.join(dir, "usage.json")
      t = described_class.new(
        max_billable_chars: 10_000,
        daily_char_cap: 4,
        state_path: state,
        v2_client: fake_client,
        min_interval_between_calls: 0,
      )
      t.translate("abcd", from: "en", to: "ko")
      expect { t.translate("e", from: "en", to: "ko") }.to(raise_error(EmTools::Core::Errors::TranslationBudgetExceededError))
    end
  end

  it "batches multiple strings within max_chars_per_request" do
    t = described_class.new(
      max_billable_chars: 100,
      max_chars_per_request: 10,
      v2_client: fake_client,
      min_interval_between_calls: 0,
    )
    out = t.translate_many(["aa", "bbb"], from: "en", to: "ko")
    expect(out).to(eq(["[ko]aa", "[ko]bbb"]))
    expect(fake_client.batches.length).to(eq(1))
  end
end
