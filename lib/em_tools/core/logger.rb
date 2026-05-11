# frozen_string_literal: true

require "logger"

module EmTools
  module Core
    # Single source of truth for +::Logger+ instances used inside the gem. Every runner / service /
    # client that previously constructed its own +::Logger.new($stderr, progname: ...)+ default
    # should call {EmTools::Core::Logger.for} so log level / output / format are configurable
    # centrally.
    #
    # Configuration (resolved at +.for+ call time, so tests can change it via +ENV+):
    #
    #   * +EM_TOOLS_LOG_LEVEL+    — +debug+ | +info+ | +warn+ | +error+ | +fatal+ (default +info+).
    #   * +EM_TOOLS_LOG_OUTPUT+   — file path; when blank/unset, +$stderr+ is used.
    #   * +EM_TOOLS_LOG_FORMAT+   — +text+ (default) | +json+.
    #
    # Usage:
    #
    #   logger = EmTools::Core::Logger.for(progname: 'unpublish-candidates')
    #   logger.info('starting source=AMZ_AE')
    #
    # Tests can call +EmTools::Core::Logger.silent!+ inside +before(:all)+ /
    # +RSpec.configure+ to suppress noise.
    module Logger
      LEVELS = {
        "debug" => ::Logger::DEBUG,
        "info" => ::Logger::INFO,
        "warn" => ::Logger::WARN,
        "error" => ::Logger::ERROR,
        "fatal" => ::Logger::FATAL,
      }.freeze

      DEFAULT_LEVEL = ::Logger::INFO

      class << self
        # Build a +::Logger+ scoped to a +progname+. Returns a fresh logger each call (cheap) so
        # callers can stash it on +@logger+ without worrying about cross-component bleed.
        def for(progname: nil, level: nil, output: nil, format: nil)
          logger = ::Logger.new(output || resolve_output)
          logger.progname = progname.to_s if progname
          logger.level = resolve_level(level)
          logger.formatter = resolve_formatter(format)
          logger
        end

        # Process-wide default logger; useful for one-off events outside a runner.
        def root
          @root ||= self.for(progname: "em-tools")
        end

        # Replace the root logger (e.g. inject a +StringIO+ in specs).
        attr_writer :root

        # Suppresses all log output below +FATAL+ on subsequent +.for+ calls and on +.root+.
        # Convenient for noisy specs.
        def silent!
          ENV["EM_TOOLS_LOG_LEVEL"] = "fatal"
          @root = ::Logger.new(IO::NULL)
          @root.level = ::Logger::FATAL
          @root
        end

        private

        def resolve_level(explicit)
          return explicit if explicit.is_a?(Integer)
          return LEVELS.fetch(explicit.to_s.downcase) { DEFAULT_LEVEL } if explicit

          env = ENV["EM_TOOLS_LOG_LEVEL"].to_s.strip.downcase
          LEVELS.fetch(env) { DEFAULT_LEVEL }
        end

        def resolve_output
          path = ENV["EM_TOOLS_LOG_OUTPUT"].to_s.strip
          return $stderr if path.empty?
          return $stderr if path.casecmp("stderr").zero?
          return $stdout if path.casecmp("stdout").zero?

          # Append-mode file. We deliberately do not rotate — leave that to the host (logrotate,
          # systemd, k8s sidecar). The handle is intentionally long-lived (lifetime of the
          # logger) and not closed here, so the block form would be wrong.
          # rubocop:disable Style/FileOpen
          File.open(path, File::WRONLY | File::APPEND | File::CREAT).tap { |f| f.sync = true }
          # rubocop:enable Style/FileOpen
        end

        def resolve_formatter(format)
          fmt = (format || ENV["EM_TOOLS_LOG_FORMAT"]).to_s.strip.downcase
          fmt == "json" ? json_formatter : text_formatter
        end

        def text_formatter
          lambda do |severity, time, progname, msg|
            ts = time.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
            tag = progname.to_s.empty? ? "" : " [#{progname}]"
            "#{ts} #{severity.ljust(5)}#{tag} #{format_message(msg)}\n"
          end
        end

        def json_formatter
          require "json"
          ->(severity, time, progname, msg) { "#{::JSON.generate(json_payload(severity, time, progname, msg))}\n" }
        end

        def json_payload(severity, time, progname, msg)
          payload = { "time" => time.utc.iso8601(3), "level" => severity, "message" => format_message(msg) }
          payload["progname"] = progname.to_s unless progname.to_s.empty?
          payload
        end

        def format_message(msg)
          case msg
          when ::String then msg
          when ::Exception then "#{msg.class}: #{msg.message}"
          else msg.inspect
          end
        end
      end
    end
  end
end
