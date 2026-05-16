# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Lazada
      module Cli
        # +em-tools lazada products export+ — Lazada products from Elasticsearch as NDJSON.
        class ExportProducts < Dry::CLI::Command
          desc "Stream Lazada marketplace products from Elasticsearch as NDJSON"

          option :marketplace,
            aliases: ["-m"],
            default: "th",
            desc: "Marketplace code (th, my, …) — see lazada_marketplaces in settings.yml"
          option :output, aliases: ["-o"], desc: "Write NDJSON to file instead of stdout"
          option :batch_size,
            aliases: ["-b"],
            default: "1000",
            desc: "Documents per request (default: 1000)"
          option :source,
            aliases: ["-s"],
            desc: "Override products_query.source_value (blank = profile / match_all)"
          option :url,
            aliases: ["-u"],
            desc: "Elasticsearch base URL override (default: exporters.<exporter_key> / env)"

          option :no_keyword_filter,
            type: :boolean,
            default: false,
            desc: "Disable prohibited-keyword policy"
          option :force_keyword_filter,
            type: :boolean,
            default: false,
            desc: "Enable keyword policy even when profile default is off"
          option :keywords_path,
            desc: "Load prohibited keywords from a local file (skips admin API)"
          option :blocked_output,
            desc: "Rejected docs NDJSON path (default beside --output)"

          option :title_field, desc: "Override blacklist title field (default: profile)"
          option :brand_field, desc: "Override blacklist brand field (default: profile)"

          option :for_upload,
            type: :boolean,
            default: false,
            desc: "Apply upload filters + marketplace-specific formatter"
          option :inventory_source,
            desc: "Override Spree inventory source for uploaded-ID skip (default: profile)"
          option :no_validate_for_upload,
            type: :boolean,
            default: false,
            desc: "Skip StandardProduct validation (for-upload only)"

          option :translation_index,
            desc: "Translation sidecar index (enables merge when profile translate_by_default or use --force-translate)"
          option :translation_es_url, desc: "Optional ES cluster URL for translation index"
          option :no_translate,
            type: :boolean,
            default: false,
            desc: "Never merge title_en from translation index"
          option :force_translate,
            type: :boolean,
            default: false,
            desc: "Merge title_en when translation index is configured even if translate_by_default is off"
          option :translation_source_field, desc: "Override translation doc id field (default: profile)"
          option :translation_source_product_id_field, desc: "Override translation doc id field"

          example [
            "-m th -u 'http://user:pass@host:9200' --for-upload -o tmp/lazada_th.ndjson",
            "-m my --no-keyword-filter -o tmp/lazada_my_raw.ndjson",
          ]

          def call(marketplace: "th", output: nil, batch_size: "1000", source: nil, url: nil,
            no_keyword_filter: false, force_keyword_filter: false, keywords_path: nil, blocked_output: nil,
            title_field: nil, brand_field: nil,
            for_upload: false, inventory_source: nil, no_validate_for_upload: false,
            translation_index: nil, translation_es_url: nil,
            no_translate: false, force_translate: false,
            translation_source_field: nil, translation_source_product_id_field: nil, **)
            ExportSupport.perform(
              marketplace: marketplace,
              output: output,
              batch_size: batch_size,
              source: source,
              keywords_path: keywords_path,
              blocked_output: blocked_output,
              title_field: title_field,
              brand_field: brand_field,
              for_upload: for_upload,
              inventory_source: inventory_source,
              validate_for_upload: !no_validate_for_upload,
              elasticsearch_url: url,
              no_keyword_filter: no_keyword_filter,
              force_keyword_filter: force_keyword_filter,
              translation_index: translation_index,
              translation_es_url: translation_es_url,
              no_translate: no_translate,
              force_translate: force_translate,
              translation_source_field: translation_source_field,
              translation_source_product_id_field: translation_source_product_id_field,
            )
          end
        end
      end
    end
  end
end
