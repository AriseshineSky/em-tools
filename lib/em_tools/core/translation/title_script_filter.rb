# frozen_string_literal: true

module EmTools
  module Core
    module Translation
      # Heuristic filter for "does this +title+ look Korean / Japanese enough to send
      # to Google Translate?". This avoids billing English titles; it is **not** a
      # substitute for server-side language detection (use +from: nil+ in the API for
      # that once you decide to translate).
      module TitleScriptFilter
        HANGUL = /[\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]/
        KANA = /[\u3040-\u309F\u30A0-\u30FF]/
        CJK_UNIFIED = /[\u4E00-\u9FFF\u3400-\u4DBF]/

        extend self

        # @param text [String]
        # @param langs [Array<String>] e.g. +%w[ko ja]+
        # @return [Boolean]
        def allow?(text, langs)
          t = text.to_s
          return false if t.strip.empty?

          codes = langs.map { |x| x.to_s.strip.downcase }.reject(&:empty?)
          return false if codes.empty?

          codes.any? { |code| matches_code?(t, code) }
        end

        private

        def matches_code?(text, code)
          case code
          when "ko" then text.match?(HANGUL)
          when "ja" then text.match?(KANA) || (text.match?(CJK_UNIFIED) && !text.match?(HANGUL))
          else
            false
          end
        end
      end
    end
  end
end
