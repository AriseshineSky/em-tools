# frozen_string_literal: true

require "ahocorasick-rust"

module EmTools
  module Core
    module Blacklist
      # Namespace for blacklist matching engines. Add new algorithms (regex, exact-set, etc.)
      # by dropping a sibling file in here; +Strategy::*+ classes pick which one to use.
      module Engine
        # Small adapter around the native Aho-Corasick gem. It owns keyword normalization and
        # the empty-pattern edge case so strategies can stay focused on "what text should be
        # searched", not "how the automaton is built".
        class AhoCorasick
          attr_reader :keyword_count

          def initialize(keywords, case_sensitive: false)
            @case_sensitive = case_sensitive
            @patterns = normalize_keywords(keywords)
            @keyword_count = @patterns.size
            @automation = @patterns.empty? ? nil : AhoCorasickRust.new(@patterns)
          end

          def blocked?(text)
            return false unless @automation

            @automation.match?(normalize_text(text))
          end

          def lookup(text)
            return [] unless @automation

            @automation.lookup(normalize_text(text)).uniq
          end

          private

          def normalize_keywords(keywords)
            Array(keywords)
              .map { |keyword| normalize_text(keyword).strip }
              .reject(&:empty?)
              .uniq
          end

          def normalize_text(text)
            value = text.to_s
            @case_sensitive ? value : value.downcase
          end
        end
      end
    end
  end
end
