# frozen_string_literal: true

module EmTools
  module Core
    # Shared exception types used across pipelines, runners, and CLI commands.
    # All of these descend from {EmTools::Error}, so callers can rescue either
    # the concrete class or the gem-wide base class.
    module Errors
      # Raised when an operation cannot proceed because of missing or invalid
      # configuration: an unset environment variable, missing credentials,
      # missing file, etc. The CLI runner ({EmTools::Core::Cli::Runner}) catches
      # this and prints a clean +error: <msg>+ + +exit 1+ instead of dumping a
      # Ruby stack trace.
      class ConfigurationError < EmTools::Error; end

      # Raised when a pipeline ran end-to-end but produced an empty / unusable
      # result that the caller treats as a hard failure (e.g. zero seed ASINs
      # loaded for a marketplace).
      class EmptyResultError < EmTools::Error; end

      # Raised when {EmTools::Core::Translation::BudgetedTranslator} is not
      # configured (zero cap / disabled) or credentials are missing.
      class TranslationDisabledError < EmTools::Error; end

      # Raised when a translate request would exceed a session or daily
      # character budget (Google bills per character).
      class TranslationBudgetExceededError < EmTools::Error; end
    end
  end
end
