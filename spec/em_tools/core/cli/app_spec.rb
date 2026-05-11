# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Core::Cli::App) do
  describe "#start" do
    it "dispatches through the supplied command registry" do
      stub_const("CoreCliAppSpecCommand", Class.new { def run(_argv); end })
      command = class_double(CoreCliAppSpecCommand)
      command_instance = instance_double(CoreCliAppSpecCommand)
      registry = instance_double(EmTools::Core::Cli::CommandRegistry)

      allow(registry).to(receive(:fetch).with("inventory-sync").and_return(
        EmTools::Core::Cli::CommandRegistry::Command.new(
          name: "inventory-sync",
          klass: command,
          section: "Inventory & object storage",
          source: :core,
        ),
      ))
      allow(command).to(receive(:new).and_return(command_instance))
      expect(command_instance).to(receive(:run).with(["--dry-run"]))

      described_class.new(["inventory-sync", "--dry-run"], registry: registry).start
    end
  end
end
