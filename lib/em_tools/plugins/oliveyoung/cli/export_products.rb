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
        #
        # For the dedicated **ES → uploadable NDJSON** flow, prefer
        # +em-tools oliveyoung products build-upload+.
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

          option :for_upload,
            type: :boolean,
            default: false,
            desc: "Shape rows for storefront upload (Oliveyoung rules: filter, StandardProduct, price)"
          option :inventory_source,
            default: "oliveyoung",
            desc: "Spree inventory CSV source when skipping already-uploaded IDs (with --for-upload)"
          option :no_validate_for_upload,
            type: :boolean,
            default: false,
            desc: "Skip EmProduct::StandardProduct validation (for-upload only; default: validate)"

          option :translation_index,
            desc: "Elasticsearch index with title translations (+_id+ = hash(source, source_product_id)); " \
              "merge +title_en+ into each exported row before upload shaping"
          option :translation_es_url,
            desc: "Optional Elasticsearch base URL for --translation-index (default: same cluster as products)"
          option :translation_source_field,
            default: "source",
            desc: "Product field for source key when resolving translation _id (default: source)"
          option :translation_source_product_id_field,
            default: "source_product_id",
            desc: "Product field for stable id within source (default: source_product_id)"

          example [
            "                                          # NDJSON to stdout, keyword filter on",
            "-o tmp/oy.ndjson                          # write to file",
            "--no-keyword-filter                       # skip the policy",
            "--keywords-path tmp/blacklist.txt         # use a local keyword file",
            "-s OLIVEYOUNG --blocked-output tmp/oy.blocked.ndjson",
            "--for-upload -o tmp/oy_upload.ndjson    # Oliveyoung upload pipeline on export",
          ]

          def call(output: nil, batch_size: "1000", source: nil,
            keyword_filter: true, keywords_path: nil, blocked_output: nil,
            title_field: "title", brand_field: "brand",
            for_upload: false, inventory_source: "oliveyoung", no_validate_for_upload: false,
            translation_index: nil, translation_es_url: nil,
            translation_source_field: "source", translation_source_product_id_field: "source_product_id", **)
            ExportSupport.perform(
              output: output,
              batch_size: batch_size,
              source: source,
              keyword_filter: keyword_filter,
              keywords_path: keywords_path,
              blocked_output: blocked_output,
              title_field: title_field,
              brand_field: brand_field,
              for_upload: for_upload,
              inventory_source: inventory_source,
              validate_for_upload: !no_validate_for_upload,
              translation_index: translation_index,
              translation_es_url: translation_es_url,
              translation_source_field: translation_source_field,
              translation_source_product_id_field: translation_source_product_id_field,
            )
          end
        end
      end
    end
  end
end
