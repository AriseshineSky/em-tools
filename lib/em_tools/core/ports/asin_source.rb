# frozen_string_literal: true

module EmTools
  module Core
    module Ports
      # Duck-typed contract for objects that stream ASIN strings.
      module AsinSource
        include Enumerable

        def each
          raise NotImplementedError, "#{self.class} must implement #each"
        end

        def describe
          { kind: self.class.name }
        end
      end
    end
  end
end
