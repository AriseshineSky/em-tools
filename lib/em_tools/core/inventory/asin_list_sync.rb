# frozen_string_literal: true

module EmTools
  module Core
    module Inventory
      # Syncs a line-oriented ASIN seed file (e.g. +gs://.../sources/AMZ_DE.txt+) into Elasticsearch.
      # Each non-empty line becomes document _id and +source_product_id+; +source+ / feed field
      # come from +source_key+ or the filename (+AMZ_DE.txt+ → +AMZ_DE+).
      class AsinListSync
        BATCH_SIZE = 2000

        def initialize(sink:, index:, source_key:, feed_field:, feed_id: nil, prune_obsolete: false,
          logger: nil)
          @sink = sink
          @index = index
          @source_key = source_key.to_s.strip
          @feed_field = feed_field.to_s
          @feed_id = feed_id.to_s.strip
          @feed_id = @source_key if @feed_id.empty?
          @prune_obsolete = prune_obsolete ? true : false
          @logger = logger || EmTools::Core::Logger.for(progname: "asin-list-sync")
          @flushed_docs = 0
        end

        # @param gs_uri [String]
        # @return [String, nil] e.g. +"AMZ_DE"+ from +.../AMZ_DE.txt+
        def self.infer_source_from_gs_uri(gs_uri)
          base = File.basename(gs_uri.to_s.split("?").first)
          if (m = base.match(/\AAMZ_([A-Za-z0-9]+)\.txt\z/i))
            return "AMZ_#{m[1].upcase}"
          end

          fallback = base.sub(/\.txt\z/i, "").tr("-", "_").upcase
          fallback.empty? ? nil : fallback
        end

        def sync_from_path(path, refresh: false)
          validate_prune_options!
          batch_id = Time.now.to_i
          buffer = []
          AsinListReader.read!(path).each do |asin|
            append_asin!(buffer, asin, batch_id)
          end
          flush(buffer)
          after_bulk_refresh_prune(batch_id)
          @sink.refresh(index: @index) if refresh && @sink.respond_to?(:refresh)
        end

        private

        def validate_prune_options!
          return unless @prune_obsolete

          missing = []
          missing << "delete_by_query" unless @sink.respond_to?(:delete_by_query)
          missing << "refresh" unless @sink.respond_to?(:refresh)
          return if missing.empty?

          raise ArgumentError, "sink must respond to #{missing.join(' and ')} when prune_obsolete is true"
        end

        def after_bulk_refresh_prune(batch_id)
          return unless @prune_obsolete

          @sink.refresh(index: @index)
          @sink.delete_by_query(index: @index, body: obsolete_feed_body(batch_id))
        end

        def obsolete_feed_body(batch_id)
          {
            query: {
              bool: {
                filter: [
                  { term: { "#{@feed_field}.keyword" => @feed_id } },
                  { bool: { must_not: { term: { "sync_batch_id" => batch_id } } } },
                ],
              },
            },
          }
        end

        def append_asin!(buffer, asin, batch_id)
          doc = {
            "source_product_id" => asin,
            "source" => @source_key,
            @feed_field => @feed_id,
            "sync_batch_id" => batch_id,
            "synced_at" => Time.now.utc.iso8601,
          }
          buffer << {
            update: {
              _index: @index,
              _id: asin,
              data: { doc: doc, doc_as_upsert: true },
            },
          }
          flush(buffer) if buffer.size >= BATCH_SIZE
        end

        def flush(buffer)
          return if buffer.empty?

          batch_size = buffer.size
          response = @sink.bulk(body: buffer.dup)
          buffer.clear
          @flushed_docs += batch_size
          @logger.info { "[Flushed] index=#{@index} batch=#{batch_size} total=#{@flushed_docs}" }
          return unless response.is_a?(Hash) && response["errors"]

          bad = (response["items"] || []).filter_map { |i| i if i.values.first["error"] }.first(5)
          raise "Bulk sink reported errors (sample): #{bad.inspect}"
        end
      end
    end
  end
end
