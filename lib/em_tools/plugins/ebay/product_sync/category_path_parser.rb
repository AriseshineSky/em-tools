# frozen_string_literal: true

module EmTools
  module Plugins
    module Ebay
      module ProductSync
        # Parses InspireUplift-style category paths: +Home, Garden & Tools>Kitchen & Dining+.
        module CategoryPathParser
          MISSING_LABEL = "(missing categories)"
          SEPARATOR = ">"

          module_function

          # @param raw [String, nil]
          # @return [Array<String>] trimmed segments (empty when missing)
          def split_parts(raw)
            raw.to_s.split(SEPARATOR, -1).map(&:strip).reject(&:empty?)
          end

          # First category level (text before the first +>+, or whole string when flat).
          def level1(raw)
            parts = split_parts(raw)
            parts.empty? ? MISSING_LABEL : parts[0]
          end

          # First two levels joined by +>+; when only one segment, same as level1.
          def level2_path(raw)
            parts = split_parts(raw)
            return MISSING_LABEL if parts.empty?
            return parts[0] if parts.size == 1

            parts[0..1].join(SEPARATOR)
          end

          def resolve(raw)
            { level1: level1(raw), level2_path: level2_path(raw) }
          end
        end
      end
    end
  end
end
