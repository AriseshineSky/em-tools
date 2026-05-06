# frozen_string_literal: true

module Em
  module Tools
    module Processing
      # Linear composition of discrete steps (format change, cleaning, branching).
      #
      # Each +stage+ must respond to +call(record, context)+:
      # - +record+ is typically a Hash representing one logical row/document.
      # - +context+ is a shared object (often Hash) passed through unchanged; use it for
      #   configuration, +Logger+, mutable counters, or collaborators like +Blacklist::Engine+.
      #
      # Return convention:
      # - Return the next +record+ to continue.
      # - Return +:drop+ to stop the chain for this record (+Pipeline#call+ returns +:drop+).
      #
      # This stays intentionally tiny: no DSL, no magic. Prefer plain objects or lambdas.
      class Pipeline
        DROP = :drop

        def initialize(stages, on_drop: nil)
          @stages = stages.frozen? ? stages : stages.dup.freeze
          @on_drop = on_drop
        end

        def call(record, context = nil)
          final = @stages.reduce(record) do |memo, stage|
            break DROP if memo == DROP

            stage.call(memo, context)
          end
          @on_drop&.call(record, context) if final == DROP
          final
        end

        # Applies +call+ to each element; +:drop+ results are skipped.
        def filter_map(enumerable, context = nil)
          enumerable.lazy.filter_map do |item|
            out = call(item, context)
            out unless out == DROP
          end
        end
      end
    end
  end
end
