# frozen_string_literal: true

module EmTools
  module Core
    module Blacklist
      # Normalizes free text before Aho–Corasick matching (ported from
      # +em_tasks/utils/blacklist_filter.py+ +_SEPARATOR_RE+, plus +®+).
      module TextCleaner
        # Punctuation / whitespace that act as token boundaries for keyword hits.
        # Keep in sync with Python when changing; +®+ was added for titles like
        # +"ARK® Biting and Chewing"+.
        SEPARATOR_PATTERN = %r{[,;:|/\\\-_+&()\[\]{}<>"'`~!?@#$%^*=\t\n\r\u{3000}\u{FF0C}\u{FF1B}\u{FF1A}\u{00AE}]}

        extend self

        # @param text [String]
        # @return [String] separators replaced with ASCII space (no case change)
        def clean_separators(text)
          text.to_s.gsub(SEPARATOR_PATTERN, " ")
        end
      end
    end
  end
end
