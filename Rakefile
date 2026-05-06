# frozen_string_literal: true

# Load .env when dotenv is installed (optional dev dependency).
# rubocop:disable Lint/SuppressedException
begin
  require 'dotenv/load'
rescue LoadError
end
# rubocop:enable Lint/SuppressedException

require 'bundler/gem_tasks'

# Task definitions live in rakelib/*.rake (loaded automatically by Rake).

task default: %i[]
