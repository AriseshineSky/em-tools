# frozen_string_literal: true

module EmTools
  module Core
    module Translation
      # Looks up +title_en+ from a sidecar translation index keyed by {DocId} and merges it
      # into the product document hash before upload / NDJSON export formatters run.
      #
      # Uses +mget+ per **uncached** id (in-memory memo for repeated ids in one export).
      class TitleEnFromTranslationIndex
        # Builds a +#call(source)+ converter that runs +enrich+ before an optional +inner+ step.
        #
        # @param inner [#call, nil] e.g. {Pipeline::TransformChain} or formatter
        # @param product_es_client [EmTools::Clients::ElasticsearchClient] fallback when no translation URL
        def self.compose_with(inner:, product_es_client:, translation_index:, translation_elasticsearch_url: nil,
          translation_source_field: "source", translation_source_product_id_field: "source_product_id")
          idx = translation_index.to_s.strip
          return inner if idx.empty?

          tr_client =
            if translation_elasticsearch_url.to_s.strip.empty?
              product_es_client
            else
              EmTools::Clients::ElasticsearchClient.new(url: translation_elasticsearch_url)
            end
          merger = new(
            es_client: tr_client,
            translation_index: idx,
            source_field: translation_source_field,
            source_product_id_field: translation_source_product_id_field,
          )
          return merger.to_proc unless inner

          proc { |src| inner.call(merger.enrich(src)) }
        end

        # @param es_client [EmTools::Clients::ElasticsearchClient]
        # @param translation_index [String]
        # @param source_field [String] field holding the source key (default +source+)
        # @param source_product_id_field [String]
        # @param output_field [String] merged field name (default +title_en+)
        def initialize(es_client:, translation_index:, source_field: "source",
          source_product_id_field: "source_product_id", output_field: "title_en")
          @es = es_client
          @translation_index = translation_index.to_s.strip
          @source_field = source_field.to_s
          @source_product_id_field = source_product_id_field.to_s
          @output_field = output_field.to_s
          @memo = {}
        end

        # @return [Hash] shallow copy of +src+ with +title_en+ set when a translation row exists
        def enrich(src)
          h = src.is_a?(Hash) ? src : {}
          spid = dig(h, @source_product_id_field)
          src_key = dig(h, @source_field)
          return h if spid.to_s.strip.empty? || src_key.to_s.strip.empty?

          id = DocId.encode(src_key, spid)
          fetch!(id) unless @memo.key?(id)
          te = @memo[id]
          return h if te.nil? || te.to_s.strip.empty?

          h.merge(@output_field => te)
        end

        def to_proc
          ->(src) { enrich(src) }
        end

        private

        def dig(hash, key)
          hash[key] || hash[key.to_sym]
        end

        def fetch!(id)
          return if @memo.key?(id)

          resp = @es.mget(index: @translation_index, ids: [id])
          doc = Array(resp["docs"]).first
          found = doc.is_a?(Hash) && doc["found"] && doc["_source"].is_a?(Hash)
          @memo[id] =
            if found
              s = doc["_source"]
              te = (s["title_en"] || s[:title_en]).to_s.strip
              te.empty? ? nil : te
            end
        end
      end
    end
  end
end
