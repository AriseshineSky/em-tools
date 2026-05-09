# frozen_string_literal: true

module EmTools
  module Core
    # Tiny shim so rake task bodies stay one-liners. Boots +em_tools+, runs the block, and turns
    # well-typed +ConfigurationError+ / +EmptyResultError+ exceptions into +warn+ + +exit 1+.
    #
    # Usage from a +.rake+ file:
    #
    #   task :foo, [:arg] do |_t, args|
    #     EmTools::Core::RakeSupport.run do
    #       EmTools::SomePlugin::Pipelines::DoThing.new(arg: args[:arg]).run!
    #     end
    #   end
    module RakeSupport
      class << self
        # Yields and prints +result.to_s+ if the block returns a +RakeSupport::Result+ (or any
        # object responding to +#summary+). Any other return value is ignored.
        def run
          require 'em_tools'
          result = yield
          puts result.summary if result.respond_to?(:summary)
          result
        rescue EmTools::Core::Errors::ConfigurationError, EmTools::Core::Errors::EmptyResultError => e
          warn "error: #{e.message}"
          exit 1
        end
      end

      # Lightweight result envelope for pipelines that just need a one-line summary.
      Result = Struct.new(:summary, keyword_init: true)
    end
  end
end
