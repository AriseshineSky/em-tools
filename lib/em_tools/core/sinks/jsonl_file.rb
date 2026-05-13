# frozen_string_literal: true

require "fileutils"
require "json"

module EmTools
  module Core
    module Sinks
      # Writes one JSON object per line to a local file. The file is opened lazily
      # so constructing the sink is side-effect free (useful for dry-run manifests).
      class JsonlFile
        include Ports::RecordSink

        attr_reader :path

        def initialize(path:)
          @path = File.expand_path(path.to_s)
          @written = 0
          @io = nil
        end

        def index(record)
          io.puts(JSON.generate(record))
          @written += 1
        end

        def close
          @io&.close unless @io.closed?
        end

        def stats
          { file_written: @written }
        end

        def describe
          { kind: "file", path: @path }
        end

        private

        def io
          return @io if @io

          FileUtils.mkdir_p(File.dirname(@path))
          @io = File.open(@path, "w", encoding: "utf-8")
        end
      end
    end
  end
end
