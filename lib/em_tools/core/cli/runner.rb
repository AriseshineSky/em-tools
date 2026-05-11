# frozen_string_literal: true

module EmTools
  module Core
    module Cli
      # Tiny shim that every CLI command body wraps with so the actual command class stays a thin
      # arg-parsing layer. Yields the supplied block, prints +result.summary+ when the block returns
      # a +Runner::Result+, and turns well-typed +ConfigurationError+ / +EmptyResultError+ exceptions
      # into +warn+ + +exit 1+ (so users see a single-line error, not a Ruby stack trace).
      #
      # Usage from a CLI command class:
      #
      #   EmTools::Core::Cli::Runner.run do
      #     EmTools::SomePlugin::Pipelines::DoThing.new(arg: foo).run!
      #   end
      module Runner
        def self.run
          result = yield
          puts result.summary if result.respond_to?(:summary)
          result
        rescue EmTools::Core::Errors::ConfigurationError, EmTools::Core::Errors::EmptyResultError => e
          warn("error: #{e.message}")
          exit(1)
        end

        # Lightweight result envelope for pipelines/runners that just need a one-line summary.
        Result = Struct.new(:summary, keyword_init: true)
      end
    end
  end
end
