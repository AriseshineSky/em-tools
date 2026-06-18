# frozen_string_literal: true

require "csv"

module EmTools
  module Core
    module Inventory
      # +feed_field+ (default +inventory_feed+; Google Ads catalog uses +google_ads_feed+) is written on
      # each doc and used with +prune_obsolete+. Value defaults to each row's CSV +Source+ column (header
      # +Source+ becomes field +source+). If +source+ is blank, falls back to +:feed_id+ from options
      # (e.g. YAML override).
      class Sync
        BATCH_SIZE = 2000

        # Default target index for inventory CSV sync (overridable via +INVENTORY_INDEX+ or YAML
        # +inventory_sync.index+).
        INDEX = "em_inventory"

        ID_FIELDS = ["product_id", "sku", "asin", "id"].freeze

        def initialize(sink:, index:, **opts)
          @sink = sink
          @index = index
          @batch_size = opts.fetch(:batch_size, BATCH_SIZE)
          @id_fields = opts.fetch(:id_fields, ID_FIELDS)
          @feed_id = opts[:feed_id]
          @feed_field = opts.fetch(:feed_field, "inventory_feed").to_s
          @prune_obsolete = opts[:prune_obsolete] ? true : false
          @logger = opts[:logger] || EmTools::Core::Logger.for(progname: "inventory-sync")
          @transforms = Array(opts[:transforms]).freeze
          @flushed_docs = 0
          @docs_deleted = 0
        end

        attr_reader :flushed_docs, :docs_deleted

        def sync_from_path(csv_path, refresh: false)
          @flushed_docs = 0
          @docs_deleted = 0
          reset_feed_resolution!
          validate_prune_options!
          batch_id = Time.now.to_i
          buffer = []
          foreach_csv_row(csv_path) { |row| append_row!(buffer, row, batch_id) }
          flush(buffer)
          after_bulk_refresh_prune(batch_id)
          @sink.refresh(index: @index) if refresh && @sink.respond_to?(:refresh)
          sync_result(batch_id)
        end

        def sync_from_io(io, refresh: false)
          @flushed_docs = 0
          @docs_deleted = 0
          reset_feed_resolution!
          validate_prune_options!
          batch_id = Time.now.to_i
          buffer = []
          csv_enum(io) { |row| append_row!(buffer, row, batch_id) }
          flush(buffer)
          after_bulk_refresh_prune(batch_id)
          @sink.refresh(index: @index) if refresh && @sink.respond_to?(:refresh)
          sync_result(batch_id)
        end

        private

        def reset_feed_resolution!
          @csv_resolved_feed = nil
        end

        def validate_prune_options!
          return unless @prune_obsolete

          missing = []
          missing << "delete_by_query" unless @sink.respond_to?(:delete_by_query)
          missing << "refresh" unless @sink.respond_to?(:refresh)
          return if missing.empty?

          raise ArgumentError, "sink must respond to #{missing.join(" and ")} when prune_obsolete is true"
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
              "prune_obsolete needs a non-empty #{@feed_field}: set CSV Source column on rows or pass feed_id"
          end

          response = @sink.delete_by_query(index: @index, body: obsolete_feed_body(fid, batch_id))
          @docs_deleted = response["deleted"].to_i if response.is_a?(Hash)
        end

        def sync_result(batch_id)
          {
            flushed_docs: @flushed_docs,
            docs_deleted: @docs_deleted,
            sync_batch_id: batch_id,
          }
        end

        def obsolete_feed_body(fid, batch_id)
          {
            query: {
              bool: {
                filter: [
                  { term: { "#{@feed_field}.keyword" => fid } },
                  { bool: { must_not: { term: { "sync_batch_id" => batch_id } } } },
                ],
              },
            },
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
          doc = apply_transforms(doc)
          return if doc.nil?

          register_resolved_inventory_feed!(doc)
          id = document_id(doc)
          return if id.nil? || id.empty?

          buffer << bulk_update_action(id, doc)
          flush(buffer) if buffer.size >= @batch_size
        end

        # Run every configured transform against +doc+ in declared order. Each transform
        # follows the +#call(doc) -> doc+ contract; returning +nil+ drops the row entirely.
        def apply_transforms(doc)
          @transforms.each do |t|
            doc = t.call(doc)
            return doc if doc.nil?
          end
          doc
        end

        def build_doc(row, batch_id)
          doc = row_to_doc_hash(row)
          doc["sync_batch_id"] = batch_id
          doc["synced_at"] = Time.now.utc.iso8601
          feed = resolve_feed_value(doc)
          doc[@feed_field] = feed unless feed.empty?
          doc
        end

        # When +feed_id+ is configured (CLI / YAML / +INVENTORY_FEED_ID+) it is the canonical
        # value for every row, overriding whatever the CSV +Source+ column says. Otherwise the
        # row's own +Source+ column is used.
        def resolve_feed_value(doc)
          pinned = @feed_id.to_s.strip
          return pinned unless pinned.empty?

          doc["source"].to_s.strip
        end

        # Enforce a single feed value per CSV (otherwise +prune_obsolete+ would delete the wrong docs).
        # Case-only mismatches (+"Ebay_US"+ vs +"EBAY_US"+) are treated as the same source and
        # silently normalized to the first-seen casing; truly different values raise so the operator
        # must pin +feed_id+ explicitly.
        def register_resolved_inventory_feed!(doc)
          f = doc[@feed_field].to_s.strip
          return if f.empty?

          if @csv_resolved_feed.nil?
            @csv_resolved_feed = f
          elsif @csv_resolved_feed.casecmp(f).zero?
            doc[@feed_field] = @csv_resolved_feed
          else
            raise ArgumentError,
              "inventory CSV mixes Source values: #{@csv_resolved_feed.inspect} vs #{f.inspect} " \
                "(set feed_id / INVENTORY_FEED_ID to pin a canonical value)"
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
          s = raw.to_s.strip.gsub(/\s+/, "_")
          return "" if s.empty?

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
                doc_as_upsert: true,
              },
            },
          }
        end

        # -- bulk-then-log-then-validate is one atomic step
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
        # rubocop:enable Metrics/AbcSize
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
