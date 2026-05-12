# frozen_string_literal: true

require "optparse"

module EmTools
  module Core
    module Plugin
      module Cli
        # Optional base class for plugin CLI commands.
        #
        # Captures the bits every plugin CLI keeps re-implementing: banner string, +--help+,
        # rejecting unexpected positional arguments, and translating
        # {EmTools::Core::Errors::ConfigurationError} to a friendly stderr message.
        #
        # Subclasses override:
        #
        #   * +banner+   — a heredoc summarising the command (string)
        #   * +configure(opts, options)+ — add OptionParser switches; +options+ is a Hash
        #   * +defaults+ — initial +options+ Hash (default: +{}+)
        #   * +execute!(options, argv)+ — run the command; +argv+ holds remaining positional args
        #
        # @example
        #   class StorefrontImport < EmTools::Core::Plugin::Cli::Base
        #     def banner
        #       "Usage: em-tools storefront:import-products [--dry-run] PATH"
        #     end
        #
        #     def configure(opts, options)
        #       opts.on("--dry-run") { options[:dry_run] = true }
        #     end
        #
        #     def execute!(options, argv)
        #       Importers::Run.new(path: argv.first, dry_run: options[:dry_run]).call
        #     end
        #   end
        #
        # The class is opt-in: existing plugin commands keep working unchanged.
        class Base
          def run(argv)
            options = defaults.dup
            parser = build_parser(options)
            parser.parse!(argv)
            execute!(options, argv)
          rescue EmTools::Core::Errors::ConfigurationError => e
            warn("error: #{e.message}")
            exit(2)
          end

          # Hooks ---------------------------------------------------------------

          def banner
            "Usage: em-tools <command> [options]"
          end

          def defaults
            {}
          end

          def configure(_opts, _options); end

          def execute!(_options, _argv)
            raise NotImplementedError, "#{self.class.name}#execute!"
          end

          private

          def build_parser(options)
            OptionParser.new do |opts|
              opts.banner = banner
              configure(opts, options)
              opts.on_tail("-h", "--help") do
                puts opts
                exit(0)
              end
            end
          end
        end
      end
    end
  end
end
