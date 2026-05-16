# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Oliveyoung
      module Cli
        # +em-tools oliveyoung products build-upload+ — **download** Oliveyoung
        # product rows from Elasticsearch (+oliveyoung_products+, +source=oliveyoung+)
        # and **materialize** storefront-upload NDJSON using
        # {Formatting::ProductExportFormatter} (same rules as the legacy
        # +format_oliveyoung.py+ pipeline: Spree dedupe, +StandardProduct+ check,
        # price transform).
        #
        # For raw ES NDJSON without upload shaping, use +products export+ instead.
        class BuildStoreUpload < Dry::CLI::Command
          desc "Download Oliveyoung products from Elasticsearch and write uploadable NDJSON"

          option :output,
            aliases: ["-o"],
            desc: "Output file for uploadable NDJSON (default: tmp/oliveyoung_store_upload.ndjson)"
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
            desc: "Drop products whose title/brand hits a prohibited keyword (default: on)"
          option :keywords_path,
            desc: "Load prohibited keywords from a local txt/json file"
          option :blocked_output,
            desc: "Write keyword-rejected docs as NDJSON (default beside --output)"

          option :title_field, default: "title", desc: "Source field used for keyword match"
          option :brand_field, default: "brand", desc: "Source field used for keyword match"

          option :inventory_source,
            default: "oliveyoung",
            desc: "Spree inventory CSV source for skipping already-uploaded SourceProductIDs"
          option :no_validate_for_upload,
            type: :boolean,
            default: false,
            desc: "Skip EmProduct::StandardProduct validation (default: validate)"

          option :translation_index,
            desc: "Elasticsearch translation sidecar index; merge +title_en+ before upload shaping"
          option :translation_es_url,
            desc: "Optional Elasticsearch URL for --translation-index (default: product cluster)"
          option :translation_source_field,
            default: "source",
            desc: "Product field for translation doc id (default: source)"
          option :translation_source_product_id_field,
            default: "source_product_id",
            desc: "Product field for translation doc id (default: source_product_id)"

          example [
            "-o tmp/oy_upload.ndjson                   # explicit output path",
            "                                          # uses default tmp/oliveyoung_store_upload.ndjson",
            "--no-keyword-filter --no-validate-for-upload",
          ]

          DEFAULT_OUTPUT = File.join("tmp", "oliveyoung_store_upload.ndjson")

          def call(output: nil, batch_size: "1000", source: nil,
            keyword_filter: true, keywords_path: nil, blocked_output: nil,
            title_field: "title", brand_field: "brand",
            inventory_source: "oliveyoung", no_validate_for_upload: false,
            translation_index: nil, translation_es_url: nil,
            translation_source_field: "source", translation_source_product_id_field: "source_product_id", **)
            out = output.nil? || output.to_s.strip.empty? ? DEFAULT_OUTPUT : output
            ExportSupport.perform(
              output: out,
              batch_size: batch_size,
              source: source,
              keyword_filter: keyword_filter,
              keywords_path: keywords_path,
              blocked_output: blocked_output,
              title_field: title_field,
              brand_field: brand_field,
              for_upload: true,
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
