# frozen_string_literal: true

module Em
  module Tools
    module Filters
      class BlacklistFilter
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
