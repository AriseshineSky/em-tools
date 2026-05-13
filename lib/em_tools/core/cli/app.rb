# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Core
    module Cli
      # Thin lifecycle wrapper for the +bin/em-tools+ executable.
      #
      # Builds the dry-cli command tree (see {Registry}) and dispatches +ARGV+
      # through it. Help, subcommand listing, and option parsing are all handled
      # by +dry-cli+; this class only owns the boot sequence and top-level error
      # translation.
      class App
        def self.start(argv)
          Dry::CLI.new(Registry.build).call(arguments: argv)
        rescue EmTools::Core::Errors::ConfigurationError, EmTools::Core::Errors::EmptyResultError => e
          warn("error: #{e.message}")
          exit(1)
        end
      end
    end
  end
end
