# frozen_string_literal: true

require "dry/cli"
require "fileutils"
require "json"

module EmTools
  module Core
    module Cli
      module Commands
        # +em-tools blacklist download+ — fetches the keyword blacklist from the
        # Everymarket admin API and emits it to stdout / a file.
        #
        # Required env: BLACKLIST_API_ENDPOINT, BLACKLIST_API_PATH, BLACKLIST_API_TOKEN.
        class BlacklistDownload < Dry::CLI::Command
          desc "Download the keyword blacklist from the admin API"

          option :output, aliases: ["-o"], desc: "Write to file instead of stdout"
          option :raw,
            type: :flag,
            default: false,
            desc: "Print the raw JSON response (all pages) instead of parsed keywords"

          example [
            "                                  # one keyword per line on stdout",
            "-o tmp/blacklist.txt              # write parsed list to a file",
            "--raw -o tmp/blacklist.json       # full JSON pages dump",
          ]

          def call(output: nil, raw: false, **)
            EmTools::Core::Cli::Runner.run do
              loader = EmTools::Core::Blacklist::Loader.new
              if raw
                pages = loader.fetch_pages
                location = emit(JSON.pretty_generate(pages), output)
                Runner::Result.new(summary: "Wrote #{pages.size} raw blacklist page(s) #{location}")
              else
                keywords = loader.fetch_keywords
                location = emit(keywords.join("\n") + "\n", output)
                Runner::Result.new(summary: "Downloaded #{keywords.size} blacklist keywords #{location}")
              end
            end
          end

          private

          def emit(text, output_path)
            if output_path
              dir = File.dirname(output_path)
              FileUtils.mkdir_p(dir) unless dir == "."
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
