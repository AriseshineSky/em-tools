# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Lazada
      module Cli
        # +em-tools lazada products build-upload+ — uploadable NDJSON (per-marketplace filters + format).
        class BuildUpload < Dry::CLI::Command
          desc "Download Lazada marketplace products and write storefront-upload NDJSON"

          option :marketplace,
            aliases: ["-m"],
            default: "th",
            desc: "Marketplace code (th, my, …)"
          option :output,
            aliases: ["-o"],
            desc: "Output path (default: tmp/lazada_<marketplace>_upload.ndjson)"
          option :batch_size,
            aliases: ["-b"],
            default: "1000",
            desc: "Documents per request (default: 1000)"
          option :source,
            aliases: ["-s"],
            desc: "Override products_query.source_value"
          option :url,
            aliases: ["-u"],
            desc: "Elasticsearch base URL override"

          option :no_keyword_filter,
            type: :boolean,
            default: false,
            desc: "Disable prohibited-keyword policy"
          option :force_keyword_filter,
            type: :boolean,
            default: false,
            desc: "Force keyword policy on"
          option :keywords_path, desc: "Local keyword file"
          option :blocked_output, desc: "Side file for rejected docs"

          option :title_field, desc: "Override blacklist title field"
          option :brand_field, desc: "Override blacklist brand field"

          option :inventory_source, desc: "Override Spree inventory source for skip list"
          option :no_validate_for_upload,
            type: :boolean,
            default: false,
            desc: "Skip StandardProduct validation"

          option :translation_index, desc: "Translation sidecar index"
          option :translation_es_url, desc: "ES URL for translation index"
          option :no_translate,
            type: :boolean,
            default: false,
            desc: "Disable translation merge"
          option :force_translate,
            type: :boolean,
            default: false,
            desc: "Force translation merge when index configured"
          option :translation_source_field, desc: "Translation id field override"
          option :translation_source_product_id_field, desc: "Translation id field override"

          def default_output_path(marketplace)
            safe = marketplace.to_s.downcase.gsub(/[^a-z0-9_-]/, "")
            safe = "th" if safe.empty?
            File.join("tmp", "lazada_#{safe}_upload.ndjson")
          end

          example [
            "-m th -u 'http://user:pass@host:9200' -o tmp/lazada_th_upload.ndjson",
            "-m my --force-translate --translation-index em_title_translations_my",
          ]

          def call(marketplace: "th", output: nil, batch_size: "1000", source: nil, url: nil,
            no_keyword_filter: false, force_keyword_filter: false, keywords_path: nil, blocked_output: nil,
            title_field: nil, brand_field: nil,
            inventory_source: nil, no_validate_for_upload: false,
            translation_index: nil, translation_es_url: nil,
            no_translate: false, force_translate: false,
            translation_source_field: nil, translation_source_product_id_field: nil, **)
            out =
              if output.nil? || output.to_s.strip.empty?
                default_output_path(marketplace)
              else
                output
              end

            ExportSupport.perform(
              marketplace: marketplace,
              output: out,
              batch_size: batch_size,
              source: source,
              keywords_path: keywords_path,
              blocked_output: blocked_output,
              title_field: title_field,
              brand_field: brand_field,
              for_upload: true,
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
