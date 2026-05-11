# frozen_string_literal: true

require "json"
require "optparse"
require "fileutils"

module EmTools
  module Core
    module Cli
      module Commands
        # Downloads the blacklist keyword list from the Everymarket admin API and writes it
        # somewhere useful (stdout, a flat keyword file, or the raw JSON response).
        #
        # Required env: +BLACKLIST_API_ENDPOINT+, +BLACKLIST_API_PATH+, +BLACKLIST_API_TOKEN+.
        class BlacklistDownload
          def run(argv)
            options = { output_path: nil, raw: false }

            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools blacklist-download [options]

                Download the keyword blacklist from the Everymarket admin API.

                By default prints one keyword per line on stdout. With --raw, prints the full
                decoded JSON body instead (useful for inspecting schema changes).

                Required env: BLACKLIST_API_ENDPOINT, BLACKLIST_API_PATH, BLACKLIST_API_TOKEN.

                Examples:
                  em-tools blacklist-download
                  em-tools blacklist-download -o tmp/blacklist.txt
                  em-tools blacklist-download --raw -o tmp/blacklist.json
              BANNER

              opts.on("-o", "--output PATH", "Write to file instead of stdout") do |path|
                options[:output_path] = path
              end
              opts.on("--raw", "Print the raw JSON response instead of parsed keywords") do
                options[:raw] = true
              end
              opts.on_tail("-h", "--help") do
                puts opts
                exit(0)
              end
            end

            parser.parse!(argv)

            unless argv.empty?
              warn("error: unexpected arguments: #{argv.join(" ")}")
              warn(parser.help)
              exit(1)
            end

            EmTools::Core::Cli::Runner.run do
              loader = EmTools::Core::Blacklist::Loader.new

              if options[:raw]
                pages = loader.fetch_pages
                summary = emit(JSON.pretty_generate(pages), options[:output_path])
                Runner::Result.new(summary: "Wrote #{pages.size} raw blacklist page(s) #{summary}")
              else
                keywords = loader.fetch_keywords
                summary = emit(keywords.join("\n") + "\n", options[:output_path])
                Runner::Result.new(summary: "Downloaded #{keywords.size} blacklist keywords #{summary}")
              end
            end
          end

          private

          def emit(text, output_path)
            if output_path
              FileUtils.mkdir_p(File.dirname(output_path)) unless File.dirname(output_path) == "."
              File.write(output_path, text)
              "to #{output_path}"
            else
              $stdout.write(text)
              "to stdout"
            end
          end
        end
      end
    end
  end
end
