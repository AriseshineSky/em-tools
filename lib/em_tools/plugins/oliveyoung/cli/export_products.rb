# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Oliveyoung
      module Cli
        # +em-tools oliveyoung products export+ — stream Oliveyoung products
        # (filtered to +source=oliveyoung+) from Elasticsearch as NDJSON,
        # optionally dropping docs that match the prohibited-keyword policy
        # (a.k.a. "blacklist" at the API boundary; see
        # +docs/DDD_AND_UBIQUITOUS_LANGUAGE.md+).
        class ExportProducts < Dry::CLI::Command
          desc "Stream Oliveyoung products from Elasticsearch as NDJSON"

          option :output, aliases: ["-o"], desc: "Write NDJSON to file instead of stdout"
          option :batch_size,
            aliases: ["-b"],
            default: "1000",
            desc: "Documents per request (default: 1000)"
          option :source,
            aliases: ["-s"],
            desc: "Override source filter value (default: oliveyoung)"

          option :keyword_filter,
            type: :boolean,
            default: true,
            desc: "Drop products whose title/brand hits a prohibited keyword " \
              "(default: on; --no-keyword-filter to disable)"
          option :keywords_path,
            desc: "Load prohibited keywords from a local txt/json file " \
              "(skips the admin API call)"
          option :blocked_output,
            desc: "Write rejected docs as NDJSON to this path (default: " \
              "<output>.blocked.ndjson, or tmp/oliveyoung_products.blocked.ndjson)"

          option :title_field, default: "title", desc: "Source field used for keyword match"
          option :brand_field, default: "brand", desc: "Source field used for keyword match"

          example [
            "                                          # NDJSON to stdout, keyword filter on",
            "-o tmp/oy.ndjson                          # write to file",
            "--no-keyword-filter                       # skip the policy",
            "--keywords-path tmp/blacklist.txt         # use a local keyword file",
            "-s OLIVEYOUNG --blocked-output tmp/oy.blocked.ndjson",
          ]

          def call(output: nil, batch_size: "1000", source: nil,
            keyword_filter: true, keywords_path: nil, blocked_output: nil,
            title_field: "title", brand_field: "brand", **)
            EmTools::Core::Cli::Runner.run do
              keywords = keywords_path ? EmTools::Core::Cli::Support.load_keywords(keywords_path) : nil
              exporter = EmTools::Core::PluginRegistry.fetch(:oliveyoung).products_exporter(
                source_value: source,
                apply_keyword_policy: keyword_filter,
                keywords: keywords,
                blocked_output_path: keyword_filter ? (blocked_output || default_blocked_path(output)) : nil,
                title_field: title_field,
                brand_field: brand_field,
              )
              counts = run_export!(exporter, output: output, batch_size: Integer(batch_size))
              EmTools::Core::Cli::Runner::Result.new(summary: build_summary(counts, output))
            end
          end
          # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

          private

          def run_export!(exporter, output:, batch_size:)
            if output
              exporter.to_jsonl(output, batch_size: batch_size)
            else
              exporter.write_jsonl($stdout, batch_size: batch_size)
            end
          end

          def default_blocked_path(output)
            if output.to_s.empty?
              File.join("tmp", "oliveyoung_products.blocked.ndjson")
            else
              dir = File.dirname(output)
              base = File.basename(output, File.extname(output))
              File.join(dir, "#{base}.blocked.ndjson")
            end
          end

          def build_summary(counts, output)
            destination = output || "stdout"
            base = "Wrote #{counts[:written]}/#{counts[:total]} hits to #{destination}"
            counts[:blocked].positive? ? "#{base}; blocked #{counts[:blocked]}" : base
          end
        end
      end
    end
  end
end
