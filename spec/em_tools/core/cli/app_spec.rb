# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Cli::App) do
  describe ".start" do
    it "dispatches to the dry-cli registry" do
      registry = Module.new
      runner = instance_double(Dry::CLI)

      expect(EmTools::Core::Cli::Registry).to(receive(:build).and_return(registry))
      expect(Dry::CLI).to(receive(:new).with(registry).and_return(runner))
      expect(runner).to(receive(:call).with(arguments: ["inventory", "sync", "--data"]))

      described_class.start(["inventory", "sync", "--data"])
    end

    it "translates ConfigurationError to a single-line stderr + exit 1" do
      allow(Dry::CLI).to(receive(:new).and_raise(
        EmTools::Core::Errors::ConfigurationError, "INVENTORY_INDEX is not set"
      ))

      expect { described_class.start([]) }.to(raise_error(SystemExit) do |e|
        expect(e.status).to(eq(1))
      end.and(output(/error: INVENTORY_INDEX is not set/).to_stderr))
    end

    it "translates EmptyResultError the same way" do
      allow(Dry::CLI).to(receive(:new).and_raise(
        EmTools::Core::Errors::EmptyResultError, "no products matched"
      ))

      expect { described_class.start([]) }.to(raise_error(SystemExit) do |e|
        expect(e.status).to(eq(1))
      end.and(output(/error: no products matched/).to_stderr))
    end
  end
end
