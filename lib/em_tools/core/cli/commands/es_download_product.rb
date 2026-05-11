# frozen_string_literal: true

require "optparse"

module EmTools
  module Core
    module Cli
      module Commands
        # Thin CLI wrapper for {EmTools::Core::Pipelines::ProductDownload}: just maps argv
        # to kwargs. All assembly logic (blacklist loading, dumper construction, blocked-file
        # path resolution) lives in the pipeline class.
        class EsDownloadProduct
          DEFAULTS = {
            blacklist_filter: true,
            title_field: "title",
            brand_field: "brand",
            blocked_output_path: nil,
          }.freeze

          def run(argv)
            opts = DEFAULTS.dup
            parser = build_parser(opts)
            parser.parse!(argv)

            unless argv.empty?
              warn("error: unexpected arguments: #{argv.join(" ")}")
              warn(parser.help)
              exit(1)
            end

            EmTools::Core::Cli::Runner.run do
              EmTools::Core::Pipelines::ProductDownload.new(**opts).run!
            end
          end

          private

          def build_parser(opts)
            OptionParser.new do |o|
              o.banner = <<~BANNER
                Usage: em-tools es-download-product [options]

                Dump product documents from the data cluster (DATA_ELASTICSEARCH_URL) to NDJSON.
                Filters out blacklisted products by default ("<title> <brand>" lowercased,
                Aho-Corasick); blocked rows are written to <output>.blocked.ndjson.

                Env: ES_DUMP_INDEX, ES_DUMP_OUTPUT, ES_DUMP_BATCH_SIZE,
                     BLACKLIST_API_ENDPOINT, BLACKLIST_API_PATH, BLACKLIST_API_TOKEN.
              BANNER
              o.on("--[no-]blacklist-filter", "Reject blacklisted products (default: on)") { |v| opts[:blacklist_filter] = v }
              o.on("--title-field FIELD", "Source title field (default: title)") { |v| opts[:title_field] = v }
              o.on("--brand-field FIELD", "Source brand field (default: brand)") { |v| opts[:brand_field] = v }
              o.on("--blocked-output PATH", "Blocked NDJSON path (default: <output>.blocked.ndjson)") do |v|
                opts[:blocked_output_path] = v
              end
              o.on_tail("-h", "--help") do
                puts(o)
                exit(0)
              end
            end
          end
        end
      end
    end
  end
end
