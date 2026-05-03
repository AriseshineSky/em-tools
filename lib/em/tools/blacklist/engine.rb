# frozen_string_literal: true

require "ahocorasick-rust"

module Em::Tools::Blacklist
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
