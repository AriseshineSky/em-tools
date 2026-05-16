# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Core
    module Cli
      module Commands
        # +em-tools es translate-titles INDEX+ — scan an Elasticsearch index, pick
        # documents whose +--source-field+ looks Korean/Japanese (heuristic), call
        # {EmTools::Core::Translation::BudgetedTranslator} to English.
        #
        # Writes either or both of:
        #
        # * a **sidecar translation index** (+--translation-index+) with stable +_id+
        #   from {EmTools::Core::Translation::DocId} (+source+ + +source_product_id+),
        #   storing original +title+ and +title_en+; and/or
        # * a **partial update** on the product index (+--target-field+, default +title_en+),
        #   controlled by +--also-update-product+ when a translation index is set.
        #
        # Requires Google Cloud Translation v2 credentials (ADC or +TRANSLATE_KEY+ /
        # +GOOGLE_CLOUD_KEY+) and a **positive** +EM_TRANSLATE_MAX_CHARS+ (or YAML
        # +translate.max_billable_chars+). See +.env.example+ and +examples/config/settings.example.yml+.
        class EsTranslateTitles < Dry::CLI::Command
          desc "Translate KO/JA-looking titles to English (product field and/or translation index)"

          argument :index, required: true, desc: "Elasticsearch index name"

          option :source_field,
            default: "title",
            desc: "Source field to read (supports one dot level, e.g. meta.title)"
          option :target_field,
            default: "title_en",
            desc: "Product index field for English (partial update when enabled)"
          option :langs,
            default: "ko,ja",
            desc: "Comma ISO codes; title must match script heuristic for one of these (default ko,ja)"
          option :to, default: "en", desc: "Google Translate target language (default en)"
          option :source_lang,
            desc: "Optional ISO source language for Google (default: auto-detect per title)"
          option :batch_size,
            aliases: ["-b"],
            default: "500",
            desc: "Elasticsearch PIT page size (default 500)"
          option :bulk_size,
            default: "50",
            desc: "Bulk actions per HTTP request (translation index + product updates; default 50)"
          option :url, aliases: ["-u"], desc: "Elasticsearch base URL override"
          option :data,
            type: :flag,
            default: false,
            desc: "Use DATA_ELASTICSEARCH_URL when set"
          option :dry_run,
            type: :flag,
            default: false,
            desc: "Do not write bulk updates; print counts only"
          option :overwrite,
            type: :flag,
            default: false,
            desc: "When updating the product index, skip the usual \"skip if target already set\" rule"
          option :translation_index,
            desc: "Sidecar Elasticsearch index name; each doc _id = hash(source, source_product_id)"
          option :source_key_field,
            default: "source",
            desc: "Product _source field for marketplace source key (translation index + doc id)"
          option :source_product_id_field,
            default: "source_product_id",
            desc: "Product _source field for stable product id within that source"
          option :also_update_product,
            type: :flag,
            default: false,
            desc: "When --translation-index is set, also partial-update --target-field on the product index"

          example [
            "user1_oliveyoung_products --translation-index em_title_translations",
            "user1_lotteon_products --translation-index em_title_translations --also-update-product",
          ]

          def call(index:, source_field: "title", target_field: "title_en", langs: "ko,ja",
            to: "en", source_lang: nil, batch_size: "500", bulk_size: "50", url: nil, data: false,
            dry_run: false, overwrite: false, translation_index: nil, source_key_field: "source",
            source_product_id_field: "source_product_id", also_update_product: false, **)
            EmTools::Core::Cli::Runner.run do
              job = Job.new(
                index: index,
                source_field: source_field,
                target_field: target_field,
                lang_codes: langs.split(",").map(&:strip).reject(&:empty?),
                to: to,
                from: source_lang,
                batch_size: Integer(batch_size),
                bulk_size: Integer(bulk_size),
                url: url,
                prefer_data_cluster: data,
                dry_run: dry_run,
                overwrite: overwrite,
                translation_index: translation_index,
                source_key_field: source_key_field,
                source_product_id_field: source_product_id_field,
                also_update_product: also_update_product,
              )
              EmTools::Core::Cli::Runner::Result.new(summary: job.run!)
            end
          rescue EmTools::Core::Errors::TranslationDisabledError,
                 EmTools::Core::Errors::TranslationBudgetExceededError => e
            warn("error: #{e.message}")
            exit(1)
          end

          # Orchestrates PIT scan + translate + bulk writes.
          class Job
            def initialize(index:, source_field:, target_field:, lang_codes:, to:, from:,
              batch_size:, bulk_size:, url:, prefer_data_cluster:, dry_run:, overwrite:,
              translation_index:, source_key_field:, source_product_id_field:, also_update_product:)
              @index = index.to_s
              @source_field = source_field.to_s
              @target_field = target_field.to_s
              @lang_codes = lang_codes
              @to = to.to_s
              @from = from&.to_s&.strip
              @from = nil if @from&.empty?
              @batch_size = batch_size
              @bulk_size = bulk_size
              @dry_run = dry_run
              @overwrite = overwrite
              @translation_index = translation_index&.to_s&.strip
              @translation_index = nil if @translation_index&.empty?
              @source_key_field = source_key_field.to_s
              @source_product_id_field = source_product_id_field.to_s
              @also_update_product = also_update_product
              @es = EmTools::Core::Config.elasticsearch_client(
                url: url,
                prefer_data_cluster: prefer_data_cluster,
              )
              @translator = EmTools::Core::Translation::BudgetedTranslator.from_config!
            end

            def run!
              scanned = candidates = translated = bulked = skipped_missing_ids = 0
              batch_rows = []

              flush = lambda do
                return if batch_rows.empty?

                texts = batch_rows.map { |r| r[:title] }
                outs = @translator.translate_many(texts, to: @to, from: @from)
                translated += outs.size
                unless @dry_run
                  body_lines = build_bulk_lines(batch_rows, outs)
                  flush_bulk!(body_lines)
                  bulked += batch_rows.size
                end
                batch_rows.clear
              end

              @es.iterate_all(index: @index, batch_size: @batch_size) do |hit|
                scanned += 1
                src = hit["_source"] || {}
                next if skip_hit?(src)

                title = dig_field(src, @source_field)
                next if title.to_s.strip.empty?
                next unless EmTools::Core::Translation::TitleScriptFilter.allow?(title, @lang_codes)

                if @translation_index
                  sk = dig_field(src, @source_key_field)
                  spid = dig_field(src, @source_product_id_field)
                  if sk.to_s.strip.empty? || spid.to_s.strip.empty?
                    skipped_missing_ids += 1
                    next
                  end
                end

                candidates += 1
                row = { hit_id: hit["_id"], title: title }
                if @translation_index
                  row[:source] = dig_field(src, @source_key_field).to_s.strip
                  row[:source_product_id] = dig_field(src, @source_product_id_field).to_s.strip
                  row[:tr_id] = EmTools::Core::Translation::DocId.encode(row[:source], row[:source_product_id])
                end
                batch_rows << row
                flush.call if batch_rows.size >= @bulk_size
              end
              flush.call

              parts = [
                "index=#{@index} scanned=#{scanned} matched_lang_heuristic=#{candidates}",
                "translated_strings=#{translated}",
              ]
              parts << "skipped_missing_source_keys=#{skipped_missing_ids}" if @translation_index
              parts << "bulk_docs=#{bulked}" unless @dry_run
              parts << "dry_run=true" if @dry_run
              parts.join(" ")
            end

            private

            def writes_translation_index?
              !@translation_index.nil?
            end

            def updates_product_index?
              return true unless writes_translation_index?

              @also_update_product
            end

            def skip_hit?(source)
              return false unless updates_product_index?
              return false if @overwrite

              v = dig_field(source, @target_field)
              !v.to_s.strip.empty?
            end

            def build_bulk_lines(batch_rows, outs)
              body_lines = []
              batch_rows.each_with_index do |row, i|
                translated = outs[i]
                if writes_translation_index?
                  doc = EmTools::Core::Translation::TranslationIndexDoc.build(
                    source: row[:source],
                    source_product_id: row[:source_product_id],
                    title: row[:title],
                    title_en: translated,
                    target_lang: @to,
                    product_index: @index,
                  )
                  body_lines << JSON.generate("index" => { "_index" => @translation_index, "_id" => row[:tr_id] })
                  body_lines << JSON.generate(doc)
                end
                if updates_product_index?
                  body_lines << JSON.generate("update" => { "_index" => @index, "_id" => row[:hit_id] })
                  body_lines << JSON.generate("doc" => { @target_field => translated })
                end
              end
              body_lines
            end

            def dig_field(hash, path)
              parts = path.split(".", 2)
              return hash[parts[0]] || hash[parts[0].to_sym] if parts.size == 1

              inner = hash[parts[0]] || hash[parts[0].to_sym]
              return unless inner.is_a?(Hash)

              inner[parts[1]] || inner[parts[1].to_sym]
            end

            def flush_bulk!(body_lines)
              return if body_lines.empty?

              body = "#{body_lines.join("\n")}\n"
              @es.bulk(body: body)
            end
          end
        end
      end
    end
  end
end
