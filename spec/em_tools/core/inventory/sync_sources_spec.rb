# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Inventory::SyncSources) do
  around do |example|
    prev = ENV.fetch("APP_ENV", nil)
    ENV["APP_ENV"] = "development"
    example.run
    prev ? ENV["APP_ENV"] = prev : ENV.delete("APP_ENV")
  end

  it "loads inventory URIs from merged settings when no path is given" do
    entries = described_class.load!
    expect(entries).not_to(be_empty)
    expect(entries.first.gs_uri).to(match(%r{\Ags://}i))
  end
end
