# frozen_string_literal: true

module EmTools
  # Top-level base class for every exception that em-tools raises on its own
  # behalf. CLI commands and library callers can rescue +EmTools::Error+ to
  # catch any em-tools-specific failure without also catching unrelated
  # +StandardError+ subclasses (Net::HTTP, Errno, etc).
  #
  # Concrete subclasses live under +EmTools::Core::Errors+:
  #
  #   * +EmTools::Core::Errors::ConfigurationError+ - missing / invalid env.
  #   * +EmTools::Core::Errors::EmptyResultError+   - pipeline produced nothing.
  class Error < StandardError; end
end
