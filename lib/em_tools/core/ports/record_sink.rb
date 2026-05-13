# frozen_string_literal: true

module EmTools
  module Core
    module Ports
      # Duck-typed contract for destinations that accept one record at a time.
      module RecordSink
        def index(_record)
          raise NotImplementedError, "#{self.class} must implement #index"
        end

        def close; end

        def stats
          {}
        end

        def describe
          { kind: self.class.name }
        end
      end
    end
  end
end
