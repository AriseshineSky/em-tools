# frozen_string_literal: true

module EmTools
  module Core
    module Blacklist
      # Aho-Corasick blacklist matcher. Same wire-shape as +Engine+ but kept distinct because
      # +Engine+ historically loads from API while +Filter+ wraps a caller-provided keyword set
      # (e.g. inside +ProductImporter+).
      class Filter
        def initialize(keywords)
          @automation = AhoCorasickRust.new(keywords)
        end

        def blocked?(text)
          @automation.match?(text)
        end

        def lookup(text)
          @automation.lookup(text)
        end
      end
    end
  end
end
