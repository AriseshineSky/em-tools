# frozen_string_literal: true

module EmTools
  module Core
    # Shared exception types used across runners, pipelines, and rake tasks.
    module Errors
      # Raised when an operation cannot proceed because of a missing / invalid env var, missing
      # credentials, missing file, etc. Rake tasks (and other callers) catch this to print a
      # clean +error: <msg>+ and +exit 1+ instead of dumping a stack trace.
      class ConfigurationError < StandardError; end

      # Raised when a pipeline ran end-to-end but produced an empty / unusable result that the
      # caller treats as a hard failure (e.g. no seed ASINs loaded for a marketplace).
      class EmptyResultError < StandardError; end
    end
  end
end
