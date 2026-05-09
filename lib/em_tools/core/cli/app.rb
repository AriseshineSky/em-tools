# frozen_string_literal: true

module EmTools
  module Core
    module Cli
      # Plugin-aware CLI entry point.
      #
      # The dispatcher exposes a small set of built-in core commands (see {CORE_COMMANDS}) and then
      # asks every registered plugin for its own +cli_commands+ hash. Plugins win conflicts in
      # registration order (later registrations overwrite earlier names); core commands are the
      # base layer and may be overridden by a plugin if it explicitly maps the same key.
      class App
        # Core commands shipped with the engine itself, independent of any plugin.
        CORE_COMMANDS = {
          'dump' => Commands::Dump
        }.freeze

        def self.start(argv)
          new(argv).start
        end

        def initialize(argv)
          @argv = argv.dup
        end

        def start
          command = @argv.shift
          if command.nil? || command.start_with?('-')
            usage_main
            exit 1
          end

          klass = command_table[command]
          unless klass
            warn "error: unknown command: #{command}"
            usage_main
            exit 1
          end

          klass.new.run(@argv)
        end

        # Merged map of every CLI command name -> command class, after consulting every plugin
        # registered with +EmTools::Core::PluginRegistry+. Built lazily so plugins can be registered
        # after this class is loaded.
        def command_table
          @command_table ||= CORE_COMMANDS.merge(plugin_commands)
        end

        def plugin_commands
          merged = {}
          EmTools::Core::PluginRegistry.each_plugin do |plugin|
            commands = plugin.cli_commands
            next if commands.nil? || commands.empty?

            merged.merge!(commands)
          end
          merged
        end

        def usage_main
          warn build_usage
        end

        private

        def build_usage
          lines = ['Usage:']
          command_table.each_key { |name| lines << "  em-tools #{name} [...]" }
          lines << ''
          lines << 'Commands:'
          command_table.each do |name, klass|
            lines << "  #{name.ljust(46)}  (#{klass.name})"
          end
          lines.join("\n")
        end
      end
    end
  end
end
