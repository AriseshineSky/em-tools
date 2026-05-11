# frozen_string_literal: true

require "yaml"

module EmTools
  module Core
    module Blacklist
      module Rules
        # Loads source -> strategy rules for blacklist evaluation.
        #
        # The YAML file is intentionally structural config only: no API tokens, URLs, or
        # credentials. Secrets remain in .env.
        class SourceRules
          DEFAULT_PATH = File.expand_path("../../../../../config/blacklist/source_rules.yml", __dir__)

          def self.load(path: nil)
            new(path || DEFAULT_PATH)
          end

          def initialize(path)
            @path = path
            @rules = read_rules
          end

          def fetch(source)
            rule = @rules[source.to_s]
            return rule if rule

            raise EmTools::Core::Errors::ConfigurationError,
              "Unknown blacklist source rules: #{source.inspect}"
          end

          private

          def read_rules
            data = YAML.safe_load_file(@path, aliases: false) || {}
            data.fetch("sources") do
              raise EmTools::Core::Errors::ConfigurationError,
                "Blacklist rules file #{@path} must contain a sources: mapping"
            end
          rescue Errno::ENOENT
            raise EmTools::Core::Errors::ConfigurationError,
              "Blacklist rules file not found: #{@path}"
          end
        end
      end
    end
  end
end
