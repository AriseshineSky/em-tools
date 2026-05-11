# frozen_string_literal: true

module EmTools
  module Core
    module Cli
      # Thin lifecycle wrapper for the +bin/em-tools+ executable.
      #
      # Responsibilities kept here:
      #   * decide whether this is a help invocation
      #   * validate / dispatch the first CLI argument
      #   * exit with the expected status code
      #
      # Command discovery / caching lives in +CommandRegistry+ and help text
      # rendering lives in +HelpRenderer+.
      class App
        HELP_ALIASES = ["help", "-h", "--help"].freeze

        def self.start(argv)
          new(argv).start
        end

        def initialize(argv, registry: CommandRegistry.default, help_renderer: nil)
          @argv = argv.dup
          @registry = registry
          @help_renderer = help_renderer || HelpRenderer.new(registry: registry)
        end

        def start
          return print_usage_and_exit(exit_code: 0) if help_invocation?

          command = @argv.shift
          if command.nil? || command.start_with?("-")
            warn("error: missing command\n\n")
            print_usage_and_exit(exit_code: 1)
          end

          definition = @registry.fetch(command)
          unless definition
            warn("error: unknown command: #{command}\n\n")
            print_usage_and_exit(exit_code: 1)
          end

          definition.klass.new.run(@argv)
        end

        private

        def help_invocation?
          return true if @argv.empty?

          first = @argv.first
          HELP_ALIASES.include?(first)
        end

        def print_usage_and_exit(exit_code:)
          puts @help_renderer.render
          exit(exit_code)
        end
      end
    end
  end
end
