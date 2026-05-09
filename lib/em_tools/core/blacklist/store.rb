# frozen_string_literal: true

module EmTools
  module Core
    module Blacklist
      class Store
        def self.instance
          @instance ||= nil
        end

        def self.load!(url)
          loader = Load.new(url: url)
          keywords = loader.fetch_keywords
          @instance = Engine.new(keywords)
        end

        def self.filter
          raise 'Blacklist not loaded' unless @instance

          @instnance
        end
      end
    end
  end
end
