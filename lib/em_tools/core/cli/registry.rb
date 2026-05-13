# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Core
    module Cli
      # Hierarchical command tree backing the +em-tools+ executable.
      #
      # Wraps +Dry::CLI::Registry+: every entry is a path of space-separated tokens
      # ("inventory sync", "amz-uploadable filter", ...) that maps to a
      # +Dry::CLI::Command+ subclass. The registry is built once at boot from two
      # sources:
      #
      # * the static core command map below, and
      # * each plugin's +cli_commands+, prefixed by its +cli_namespace+.
      module Registry
        # Path -> Dry::CLI::Command subclass.
        #
        # Layout intent: top-level token is the *area* (resource, family, plugin),
        # subsequent tokens are the verb / sub-area. Mirrors +kubectl+ / +git+.
        CORE_COMMANDS = {
          "dump" => Commands::Dump,
          "es dump-index" => Commands::EsDumpIndex,
          "es download-product" => Commands::EsDownloadProduct,
          "inventory sync" => Commands::InventorySync,
          "inventory sync-from-gcs" => Commands::InventorySyncFromGcs,
          "gcs download-seeds" => Commands::GcsDownloadSeeds,
          "blacklist download" => Commands::BlacklistDownload,
        }.freeze

        @mutex = Mutex.new

        class << self
          # Returns the assembled +Dry::CLI::Registry+ module.
          # Memoised; +reset!+ rebuilds it (test-only).
          def build
            @mutex.synchronize { @registry ||= compile }
          end

          # Test hook: throw away the cached tree so the next +build+ rescans plugins.
          def reset!
            @mutex.synchronize { @registry = nil }
          end

          private

          def compile
            commands_module = Module.new do
              extend Dry::CLI::Registry
            end
            register_core!(commands_module)
            register_plugins!(commands_module)
            commands_module
          end

          def register_core!(commands_module)
            CORE_COMMANDS.each { |path, klass| commands_module.register(path, klass) }
          end

          def register_plugins!(commands_module)
            EmTools::Core::PluginRegistry.each_plugin do |plugin|
              ns = plugin.cli_namespace.to_s.strip
              raise InvalidPluginNamespaceError, plugin.name.inspect if ns.empty?

              plugin.cli_commands.each do |sub, klass|
                full_path = "#{ns} #{sub}".strip
                commands_module.register(full_path, klass)
              end
            end
          end
        end

        class InvalidPluginNamespaceError < StandardError; end
      end
    end
  end
end
