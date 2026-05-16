# frozen_string_literal: true

module EmTools
  module Plugins
    module Oliveyoung
      module Cli
        # Shared runner for ES → NDJSON product exports (+optional keyword policy,
        # +optional {Formatting::ProductExportFormatter}+).
        module ExportSupport
          extend self

          def default_blocked_path(output)
            if output.to_s.empty?
              File.join("tmp", "oliveyoung_products.blocked.ndjson")
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

          def perform(output:, batch_size:, source:, keyword_filter:, keywords_path:, blocked_output:,
            title_field:, brand_field:, for_upload:, inventory_source:, validate_for_upload:,
            translation_index: nil, translation_es_url: nil,
            translation_source_field: "source", translation_source_product_id_field: "source_product_id")
            EmTools::Core::Cli::Runner.run do
              keywords = keywords_path ? EmTools::Core::Cli::Support.load_keywords(keywords_path) : nil
              exporter = EmTools::Core::PluginRegistry.fetch(:oliveyoung).products_exporter(
                source_value: source,
                apply_keyword_policy: keyword_filter,
                keywords: keywords,
                blocked_output_path: keyword_filter ? (blocked_output || default_blocked_path(output)) : nil,
                title_field: title_field,
                brand_field: brand_field,
                for_upload: for_upload,
                inventory_source: inventory_source,
                validate_for_upload: validate_for_upload,
                translation_index: translation_index,
                translation_elasticsearch_url: translation_es_url,
                translation_source_field: translation_source_field,
                translation_source_product_id_field: translation_source_product_id_field,
              )
              counts = run_export!(exporter, output: output, batch_size: Integer(batch_size))
              EmTools::Core::Cli::Runner::Result.new(summary: build_summary(counts, output))
            end
          end
        end
      end
    end
  end
end
