# frozen_string_literal: true

module EmTools
  module Plugins
    module Lotteon
      module Exclusions
        # Example composable exclusion: drops documents whose +title_field+ text is
        # shorter than +min+ characters (after strip). Intended as a template for
        # adding more {ExclusionChain}-compatible rules.
        class MinTitleLength
          def initialize(min:, title_field: "title")
            @min = min
            @title_field = title_field.to_s
            raise ArgumentError, "min must be positive" unless @min.positive?
          end

          def blocked?(source)
            source.fetch(@title_field, "").to_s.strip.length < @min
          end

          def matched(source)
            return [] unless blocked?(source)

            ["min_title_length"]
          end
        end
      end
    end
  end
end
