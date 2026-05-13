# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Core
    module Cli
      module Commands
        # +em-tools es download-product+ — wrapper for {EmTools::Core::Pipelines::ProductDownload}.
        # Dumps product docs from the data cluster, applies the keyword blacklist policy,
        # and writes blocked rows to a sidecar NDJSON file.
        class EsDownloadProduct < Dry::CLI::Command
          desc "Dump products from the data cluster to NDJSON (with blacklist policy)"

          option :blacklist_filter,
            type: :boolean,
            default: true,
            desc: "Reject blacklisted products (default: on; --no-blacklist-filter to disable)"
          option :title_field, default: "title", desc: "Source title field (default: title)"
          option :brand_field, default: "brand", desc: "Source brand field (default: brand)"
          option :blocked_output, desc: "Blocked NDJSON path (default: <output>.blocked.ndjson)"

          example [
            "                                          # uses ES_DUMP_INDEX / ES_DUMP_OUTPUT",
            "--no-blacklist-filter                     # skip the blacklist policy",
            "--blocked-output tmp/blocked.ndjson       # custom path for blocked rows",
          ]

          def call(blacklist_filter: true, title_field: "title", brand_field: "brand",
            blocked_output: nil, **)
            EmTools::Core::Cli::Runner.run do
              EmTools::Core::Pipelines::ProductDownload.new(
                blacklist_filter: blacklist_filter,
                title_field: title_field,
                brand_field: brand_field,
                blocked_output_path: blocked_output,
              ).run!
            end
          end
        end
      end
    end
  end
end
