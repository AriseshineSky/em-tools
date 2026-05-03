# frozen_string_literal: true

module Em::Tools::Filters
  class BlacklistFilter
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
