# frozen_string_literal: true

module EmTools
  module Core
    module Translation
      # Canonical _source shape for the sidecar **translation** Elasticsearch index.
      module TranslationIndexDoc
        extend self

        # @param product_index [String, nil] originating product index name (audit only)
        def build(source:, source_product_id:, title:, title_en:, target_lang:, product_index: nil,
          updated_at: nil)
          t = updated_at || Time.now.utc
          h = {
            "source" => source.to_s,
            "source_product_id" => source_product_id.to_s,
            "title" => title.to_s,
            "title_en" => title_en.to_s,
            "target_lang" => target_lang.to_s,
            "updated_at" => t.iso8601(3),
          }
          h["product_index"] = product_index.to_s if product_index && !product_index.to_s.strip.empty?
          h
        end
      end
    end
  end
end
