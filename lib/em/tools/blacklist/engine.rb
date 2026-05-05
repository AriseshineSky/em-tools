# frozen_string_literal: true

require 'ahocorasick-rust'

module Em
  module Tools
    module Blacklist
      class Engine
        def initialize(keywords)
          @automation = AhoCorasickRust.new(keywords)
        end

        def blocked?(text)
          !@automation.match?(text)
        end

        def lookup(text)
          @automation.lookup(text)
        end
      end
    end
  end
end
