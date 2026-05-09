# frozen_string_literal: true

require 'csv'

module EmTools
  module Core
    module Inventory
      # rubocop:disable Metrics/ClassLength
      # +inventory_feed+ (used with +prune_obsolete+) defaults to each row's CSV +Source+ column (header
      # +Source+ becomes field +source+). If +source+ is blank, falls back to +:feed_id+ from options
      # (e.g. YAML override).
      class Sync
        BATCH_SIZE = 2000

        # Default target index for inventory CSV sync (overridable via +INVENTORY_INDEX+ or YAML
        # +inventory_sync.index+).
        INDEX = 'em_inventory'

        ID_FIELDS = %w[product_id sku asin id].freeze

        def initialize(sink:, index:, **opts)
          @sink = sink
          @index = index
          @batch_size = opts.fetch(:batch_size, BATCH_SIZE)
          @id_fields = opts.fetch(:id_fields, ID_FIELDS)
          @feed_id = opts[:feed_id]
          @prune_obsolete = opts[:prune_obsolete] ? true : false
          @logger = opts[:logger] || EmTools::Core::Logger.for(progname: 'inventory-sync')
          @flushed_docs = 0
        end

        def sync_from_path(csv_path, refresh: false)
          reset_feed_resolution!
          validate_prune_options!
          batch_id = Time.now.to_i
          buffer = []
          foreach_csv_row(csv_path) { |row| append_row!(buffer, row, batch_id) }
          flush(buffer)
          after_bulk_refresh_prune(batch_id)
          @sink.refresh(index: @index) if refresh && @sink.respond_to?(:refresh)
        end

        def sync_from_io(io, refresh: false)
          reset_feed_resolution!
          validate_prune_options!
          batch_id = Time.now.to_i
          buffer = []
          csv_enum(io) { |row| append_row!(buffer, row, batch_id) }
          flush(buffer)
          after_bulk_refresh_prune(batch_id)
          @sink.refresh(index: @index) if refresh && @sink.respond_to?(:refresh)
        end

        private

        def reset_feed_resolution!
          @csv_resolved_feed = nil
        end

        def validate_prune_options!
          return unless @prune_obsolete

          missing = []
          missing << 'delete_by_query' unless @sink.respond_to?(:delete_by_query)
          missing << 'refresh' unless @sink.respond_to?(:refresh)
          return if missing.empty?

          raise ArgumentError, "sink must respond to #{missing.join(' and ')} when prune_obsolete is true"
        end

        def after_bulk_refresh_prune(batch_id)
          return unless @prune_obsolete

          @sink.refresh(index: @index)
          prune_stale_documents!(batch_id)
        end

        def prune_stale_documents!(batch_id)
          fid = @csv_resolved_feed.to_s.strip
          fid = @feed_id.to_s.strip if fid.empty?
          if fid.empty?
            raise ArgumentError,
                  'prune_obsolete needs a non-empty inventory_feed: set CSV Source column on rows or pass feed_id'
          end

          @sink.delete_by_query(index: @index, body: obsolete_inventory_body(fid, batch_id))
        end

        def obsolete_inventory_body(fid, batch_id)
          {
            query: {
              bool: {
                filter: [
                  { term: { 'inventory_feed.keyword' => fid } },
                  { bool: { must_not: { term: { 'sync_batch_id' => batch_id } } } }
                ]
              }
            }
          }
        end

        def foreach_csv_row(csv_path, &block)
          CSV.foreach(csv_path, headers: true, liberal_parsing: true, &block)
        end

        def csv_enum(io, &block)
          CSV.new(io, headers: true, liberal_parsing: true).each(&block)
        end

        def append_row!(buffer, row, batch_id)
          doc = build_doc(row, batch_id)
          register_resolved_inventory_feed!(doc)
          id = document_id(doc)
          return if id.nil? || id.empty?

          buffer << bulk_update_action(id, doc)
          flush(buffer) if buffer.size >= @batch_size
        end

        def build_doc(row, batch_id)
          doc = row_to_doc_hash(row)
          doc['sync_batch_id'] = batch_id
          doc['synced_at'] = Time.now.utc.iso8601
          feed = doc['source'].to_s.strip
          feed = @feed_id.to_s.strip if feed.empty?
          doc['inventory_feed'] = feed unless feed.empty?
          doc
        end

        def register_resolved_inventory_feed!(doc)
          f = doc['inventory_feed'].to_s.strip
          return if f.empty?

          if @csv_resolved_feed.nil?
            @csv_resolved_feed = f
          elsif @csv_resolved_feed != f
            raise ArgumentError,
                  "inventory CSV mixes Source values: #{@csv_resolved_feed.inspect} vs #{f.inspect}"
          end
        end

        def row_to_doc_hash(row)
          row.to_h.each_with_object({}) do |(k, v), acc|
            key = header_to_snake(k)
            next if key.empty?

            s = v.to_s.strip
            next if s.empty?

            acc[key] = s
          end
        end

        # +ProductID+ -> +product_id+, +SourceProductID+ -> +source_product_id+ (generic CamelCase / Acronym edges).
        def header_to_snake(raw)
          s = raw.to_s.strip.gsub(/\s+/, '_')
          return '' if s.empty?

          s.gsub(/([A-Z\d])([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .downcase
        end

        def document_id(doc)
          @id_fields.each do |field|
            v = doc[field]
            next if v.nil?

            id = v.to_s.strip
            return id unless id.empty?
          end
          nil
        end

        def bulk_update_action(id, doc)
          {
            update: {
              _index: @index,
              _id: id,
              data: {
                doc: doc,
                doc_as_upsert: true
              }
            }
          }
        end

        # rubocop:disable Metrics/AbcSize -- bulk-then-log-then-validate is one atomic step
        def flush(buffer)
          return if buffer.empty?

          batch_size = buffer.size
          response = @sink.bulk(body: buffer.dup)
          buffer.clear
          @flushed_docs += batch_size
          @logger.info { "[Flushed] index=#{@index} batch=#{batch_size} total=#{@flushed_docs}" }
          return unless response.is_a?(Hash) && response['errors']

          bad = (response['items'] || []).filter_map { |i| i if i.values.first['error'] }.first(5)
          raise "Bulk sink reported errors (sample): #{bad.inspect}"
        end
        # rubocop:enable Metrics/AbcSize
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
