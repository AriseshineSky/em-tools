# frozen_string_literal: true

module EmTools
  module Plugins
    module Lazada
      module Cli
        # Shared runner for Lazada ES → NDJSON exports (+keyword policy+, +upload formatter+).
        module ExportSupport
          extend self

          def default_blocked_path(output)
            if output.to_s.empty?
              File.join("tmp", "lazada_products.blocked.ndjson")
            else
              dir = File.dirname(output)
              base = File.basename(output, File.extname(output))
              File.join(dir, "#{base}.blocked.ndjson")
            end
          end

          def run_export!(exporter, output:, batch_size:)
            if output
              exporter.to_jsonl(output, batch_size: batch_size)
            else
              exporter.write_jsonl($stdout, batch_size: batch_size)
            end
          end

          def build_summary(counts, output)
            destination = output || "stdout"
            base = "Wrote #{counts[:written]}/#{counts[:total]} hits to #{destination}"
            parts = [base]
            parts << "blocked #{counts[:blocked]}" if counts[:blocked].to_i.positive?
            parts << "filtered #{counts[:filtered]}" if counts[:filtered].to_i.positive?
            parts.join("; ")
          end

          # @param marketplace [String] +th+, +my+, or YAML-defined code
          def perform(marketplace:, output:, batch_size:, source:, keywords_path:, blocked_output:,
            title_field:, brand_field:, for_upload:, inventory_source:, validate_for_upload:,
            elasticsearch_url: nil,
            no_keyword_filter: false, force_keyword_filter: false,
            translation_index: nil, translation_es_url: nil,
            no_translate: false, force_translate: false,
            translation_source_field: nil, translation_source_product_id_field: nil)
            EmTools::Core::Cli::Runner.run do
              profile = MarketplaceProfile.fetch(marketplace)
              keywords = keywords_path ? EmTools::Core::Cli::Support.load_keywords(keywords_path) : nil

              apply_kw = keyword_filter_enabled?(
                profile,
                no_keyword_filter: no_keyword_filter,
                force_keyword_filter: force_keyword_filter,
              )

              translation_idx = resolve_translation_merge_index(
                profile,
                cli_translation_index: translation_index,
                no_translate: no_translate,
                force_translate: force_translate,
              )

              translation_url = translation_es_url.to_s.strip
              translation_url = profile.translation_elasticsearch_url if translation_url.empty?
              translation_url = nil if translation_url.to_s.strip.empty?

              plugin = EmTools::Core::PluginRegistry.fetch(:lazada)
              exporter = plugin.products_exporter(
                marketplace: marketplace,
                elasticsearch_url: elasticsearch_url,
                source_value: source,
                apply_keyword_policy: apply_kw,
                keywords: keywords,
                blocked_output_path: apply_kw ? (blocked_output || default_blocked_path(output)) : nil,
                title_field: title_field,
                brand_field: brand_field,
                for_upload: for_upload,
                inventory_source: inventory_source,
                validate_for_upload: validate_for_upload,
                translation_merge_index: translation_idx,
                translation_elasticsearch_url: translation_url,
                translation_merge: !no_translate,
                translation_source_field: translation_source_field,
                translation_source_product_id_field: translation_source_product_id_field,
              )
              counts = run_export!(exporter, output: output, batch_size: Integer(batch_size))
              EmTools::Core::Cli::Runner::Result.new(summary: build_summary(counts, output))
            end
          end

          def keyword_filter_enabled?(profile, no_keyword_filter:, force_keyword_filter:)
            return false if no_keyword_filter
            return true if force_keyword_filter

            profile.keyword_filter_default?
          end

          def resolve_translation_merge_index(profile, cli_translation_index:, no_translate:, force_translate:)
            return if no_translate

            cli = cli_translation_index.to_s.strip
            prof = profile.translation_index.to_s.strip
            idx = cli.empty? ? prof : cli
            return if idx.empty?

            explicit_cli = !cli.empty?
            return idx if explicit_cli || force_translate
            return idx if profile.translate_by_default?

            nil
          end
        end
      end
    end
  end
end
