# frozen_string_literal: true

require 'csv'

module Em
  module Tools
    # Parses inventory CSV rows and sends Elasticsearch-style bulk +update+ operations to +sink+.
    # +sink+ must respond to +bulk(body:)+ returning a Hash that may include +errors+ and +items+ (ES bulk response).
    # If +sink+ responds to +refresh(index:)+, +sync_from_path(..., refresh: true)+ will call it after the last flush.
    #
    # CSV headers are normalized to +snake_case+ (+ProductID+ -> +product_id+). +_id+ is the first non-empty
    # +product_id+, +sku+, +asin+, +id+.
    #
    # +sync_batch_id+ is one Unix timestamp per +sync_from_*+ call, stamped on every document in that run: useful
    # to see which sync job last wrote a row, compare runs, or clean up stale docs. +synced_at+ is per-row UTC time.
    class InventorySync
      INDEX = 'em_inventory'
      BATCH_SIZE = 2000

      ID_FIELDS = %w[product_id sku asin id].freeze

      def initialize(sink:, index:, batch_size: BATCH_SIZE, id_fields: ID_FIELDS)
        @sink = sink
        @index = index
        @batch_size = batch_size
        @id_fields = id_fields
      end

      def sync_from_path(csv_path, refresh: false)
        batch_id = Time.now.to_i # same value written as +sync_batch_id+ on every doc in this run
        buffer = []
        foreach_csv_row(csv_path) { |row| append_row!(buffer, row, batch_id) }
        flush(buffer)
        @sink.refresh(index: @index) if refresh && @sink.respond_to?(:refresh)
      end

      def sync_from_io(io, refresh: false)
        batch_id = Time.now.to_i # same value written as +sync_batch_id+ on every doc in this run
        buffer = []
        csv_enum(io) { |row| append_row!(buffer, row, batch_id) }
        flush(buffer)
        @sink.refresh(index: @index) if refresh && @sink.respond_to?(:refresh)
      end

      private

      def foreach_csv_row(csv_path, &block)
        CSV.foreach(csv_path, headers: true, liberal_parsing: true, &block)
      end

      def csv_enum(io, &block)
        CSV.new(io, headers: true, liberal_parsing: true).each(&block)
      end

      def append_row!(buffer, row, batch_id)
        doc = build_doc(row, batch_id)
        id = document_id(doc)
        return if id.nil? || id.empty?

        buffer << bulk_update_action(id, doc)
        flush(buffer) if buffer.size >= @batch_size
      end

      def build_doc(row, batch_id)
        row.to_h.each_with_object({}) do |(k, v), acc|
          key = header_to_snake(k)
          next if key.empty?

          s = v.to_s.strip
          next if s.empty?

          acc[key] = s
        end.merge(
          'sync_batch_id' => batch_id,
          'synced_at' => Time.now.utc.iso8601
        )
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

      def flush(buffer)
        return if buffer.empty?

        response = @sink.bulk(body: buffer.dup)
        buffer.clear
        return unless response.is_a?(Hash) && response['errors']

        bad = (response['items'] || []).filter_map { |i| i if i.values.first['error'] }.first(5)
        raise "Bulk sink reported errors (sample): #{bad.inspect}"
      end
    end
  end
end
