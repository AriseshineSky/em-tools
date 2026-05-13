# frozen_string_literal: true

require "json"

module EmTools
  module Core
    module Sinks
      # Writes records as JSONL to stdout.
      class StdoutJsonl
        include Ports::RecordSink

        def initialize(io: $stdout)
          @io = io
          @written = 0
        end

        def index(record)
          @io.puts(JSON.generate(record))
          @written += 1
        end

        def stats
          { stdout_written: @written }
        end

        def describe
          { kind: "stdout" }
        end
      end
    end
  end
end
