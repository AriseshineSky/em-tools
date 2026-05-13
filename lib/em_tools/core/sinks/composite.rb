# frozen_string_literal: true

module EmTools
  module Core
    module Sinks
      # Fan-out sink for commands that need to persist the same records to more
      # than one destination (for example local JSONL and Elasticsearch).
      class Composite
        include Ports::RecordSink

        def initialize(sinks:)
          @sinks = Array(sinks)
        end

        def index(record)
          @sinks.each { |sink| sink.index(record) }
        end

        def close
          @sinks.reverse_each(&:close)
        end

        def stats
          @sinks.each_with_object({}) { |sink, acc| acc.merge!(sink.stats) }
        end

        def describe
          { kind: "composite", sinks: @sinks.map(&:describe) }
        end
      end
    end
  end
end
