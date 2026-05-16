# frozen_string_literal: true

module EmTools
  module Plugins
    module Lotteon
      module Pipeline
        # Runs an ordered list of transforms, each +#call(source_hash)+ returning the
        # next document or +:skip+ / {Formatting::ProductExportFormatter::SKIP} to drop
        # the row (surfaced as +filtered+ on the exporter).
        class TransformChain
          SKIP = Formatting::ProductExportFormatter::SKIP

          def initialize(steps)
            steps = steps.compact
            raise ArgumentError, "TransformChain requires at least one step" if steps.empty?

            @steps = steps.freeze
          end

          def call(source)
            doc = source
            @steps.each do |step|
              doc = step.call(doc)
              return SKIP if doc == SKIP || doc == :skip
            end
            doc
          end
        end
      end
    end
  end
end
