# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Lotteon
      module Cli
        # +em-tools lotteon products build-upload-payload+ — read Lotteon products from
        # Elasticsearch, optionally apply the prohibited-keyword policy, then run
        # composable {Pipeline::ExclusionChain} / {Pipeline::TransformChain} stages
        # (YAML + Ruby; see {Pipeline::Registry}). Transforms run **format then refine**
        # (see {EmTools::Plugins::Lotteon::Plugin}). Default upload transform remains
        # {Formatting::ProductExportFormatter}. Example: +examples/config/lotteon_upload_pipeline.example.yml+.
        class BuildUploadPayload < Dry::CLI::Command
          desc "Download Lotteon products from Elasticsearch and build uploadable NDJSON"

          option :pipeline,
            desc: "YAML file defining composable exclusions/transforms (merged with CLI flags)"

          option :output,
            aliases: ["-o"],
            desc: "Output file for uploadable NDJSON (default: tmp/lotteon_upload_payload.ndjson)"
          option :batch_size,
            aliases: ["-b"],
            default: "1000",
            desc: "Documents per request (default: 1000)"

          option :keyword_filter,
            type: :boolean,
            default: true,
            desc: "Drop products whose title/brand hits a prohibited keyword (default: on)"
          option :keywords_path,
            desc: "Load prohibited keywords from a local txt/json file"
          option :blocked_output,
            desc: "Write keyword-rejected docs as NDJSON (default beside --output)"

          option :title_field, default: "title", desc: "Source field used for keyword match"
          option :brand_field, default: "brand", desc: "Source field used for keyword match"

          option :inventory_source,
            default: "lotteon",
            desc: "Spree inventory CSV source for skipping already-uploaded SourceProductIDs"
          option :no_validate_payload,
            type: :boolean,
            default: false,
            desc: "Skip EmProduct::StandardProduct validation (default: validate)"

          option :translation_index,
            desc: "Elasticsearch translation sidecar index; merge +title_en+ before transforms"
          option :translation_es_url,
            desc: "Optional Elasticsearch URL for --translation-index (default: product cluster)"
          option :translation_source_field,
            default: "source",
            desc: "Product field for translation doc id (default: source)"
          option :translation_source_product_id_field,
            default: "source_product_id",
            desc: "Product field for translation doc id (default: source_product_id)"

          DEFAULT_OUTPUT = File.join("tmp", "lotteon_upload_payload.ndjson")

          example [
            "-o tmp/lotteon_up.ndjson",
            "                                          # default output path",
            "--no-keyword-filter --no-validate-payload",
            "--pipeline examples/config/lotteon_upload_pipeline.example.yml",
          ]

          def call(output: nil, batch_size: "1000",
            keyword_filter: true, keywords_path: nil, blocked_output: nil,
            title_field: "title", brand_field: "brand",
            inventory_source: "lotteon", no_validate_payload: false,
            pipeline: nil,
            translation_index: nil, translation_es_url: nil,
            translation_source_field: "source", translation_source_product_id_field: "source_product_id", **)
            out = output.nil? || output.to_s.strip.empty? ? DEFAULT_OUTPUT : output
            keywords = keywords_path ? EmTools::Core::Cli::Support.load_keywords(keywords_path) : nil
            pipeline_cfg = pipeline && !pipeline.to_s.strip.empty? ? pipeline : nil
            blocked_path =
              if keyword_filter || pipeline_cfg
                blocked_output || default_blocked_path(out)
              end

            plugin = EmTools::Core::PluginRegistry.fetch(:lotteon)
            exporter = plugin.products_exporter(
              apply_keyword_policy: keyword_filter,
              keywords: keywords,
              blocked_output_path: blocked_path,
              title_field: title_field,
              brand_field: brand_field,
              upload_payload: true,
              inventory_source: inventory_source,
              validate_payload: !no_validate_payload,
              pipeline_config: pipeline_cfg,
              translation_index: translation_index,
              translation_elasticsearch_url: translation_es_url,
              translation_source_field: translation_source_field,
              translation_source_product_id_field: translation_source_product_id_field,
            )

            counts = exporter.to_jsonl(out, batch_size: Integer(batch_size))
            puts(summary_line(counts, out))
          end

          private

          def default_blocked_path(output)
            dir = File.dirname(output)
            base = File.basename(output, File.extname(output))
            File.join(dir, "#{base}.blocked.ndjson")
          end

          def summary_line(counts, output)
            parts = ["Wrote #{counts[:written]}/#{counts[:total]} hits to #{output}"]
            parts << "blocked #{counts[:blocked]}" if counts[:blocked].to_i.positive?
            parts << "filtered #{counts[:filtered]}" if counts[:filtered].to_i.positive?
            parts.join("; ")
          end
        end
      end
    end
  end
end
