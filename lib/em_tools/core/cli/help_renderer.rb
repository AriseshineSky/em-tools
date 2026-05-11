# frozen_string_literal: true

module EmTools
  module Core
    module Cli
      # Renders CLI help text from a command registry.
      #
      # Keeping this separate from +App+ means command dispatch stays runtime
      # logic, while command presentation can evolve independently (grouped
      # help, JSON help, docs generation, etc.).
      class HelpRenderer
        def initialize(registry:)
          @registry = registry
        end

        def render
          lines = []
          lines << "em-tools — Everymarket data platform CLI"
          lines << ""
          lines << "Usage:"
          lines << "  em-tools <command> [options]"
          lines << "  em-tools help | -h | --help"
          lines << ""
          lines << "Commands:"
          append_sections(lines)
          lines << "Run em-tools <command> --help where supported."
          lines.join("\n")
        end

        private

        def append_sections(lines)
          @registry.sections.each do |title, commands|
            next if commands.empty?

            lines << "  #{title}"
            commands.each { |command| lines << format_command(command) }
            lines << ""
          end
        end

        def format_command(command)
          "    #{command.name.ljust(42)}  #{command.klass.name}"
        end
      end
    end
  end
end
