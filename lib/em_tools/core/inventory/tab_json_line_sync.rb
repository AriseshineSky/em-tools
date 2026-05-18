# frozen_string_literal: true

require "json"

module EmTools
  module Core
    module Inventory
      # Syncs line-oriented feed files where each row is +<ignored>\\t{json}+ (Python:
      # +_, s = line.split("\\t"); json.loads(s)+). Document +_id+ is +product_id+ from the JSON.
      class TabJsonLineSync
        BATCH_SIZE = 2000

        def initialize(sink:, index:, feed_field:, feed_id: nil, source_key: nil, prune_obsolete: false,
          logger: nil)
          @sink = sink
          @index = index
          @feed_field = feed_field.to_s
          @feed_id = feed_id.to_s.strip
          @source_key = source_key.to_s.strip
          @prune_obsolete = prune_obsolete ? true : false
          @logger = logger || EmTools::Core::Logger.for(progname: "tab-json-sync")
          @flushed_docs = 0
          @skipped = 0
        end

        def sync_from_path(path, refresh: false)
          validate_prune_options!
          batch_id = Time.now.to_i
          buffer = []
          each_product(path) do |prod|
            append_product!(buffer, prod, batch_id)
          end
          flush(buffer)
          after_bulk_refresh_prune(batch_id)
          @sink.refresh(index: @index) if refresh && @sink.respond_to?(:refresh)
          @logger.info { "skipped_lines=#{@skipped}" } if @skipped.positive?
        end

        private

        def each_product(path)
          File.foreach(path, chomp: true) do |line|
            row = line.strip
            next if row.empty? || row.start_with?("#")

            tab = row.index("\t")
            unless tab
              @skipped += 1
              next
            end

            raw_json = row[(tab + 1)..].to_s.strip
            if raw_json.empty?
              @skipped += 1
              next
            end

            begin
              prod = JSON.parse(raw_json)
            rescue JSON::ParserError => e
              @skipped += 1
              @logger.warn { "skip invalid JSON: #{e.message} (#{raw_json.byteslice(0, 120)})" }
              next
            end

            yield prod unless prod.nil?
          end
        end

        def append_product!(buffer, prod, batch_id)
          unless prod.is_a?(Hash)
            @skipped += 1
            return
          end

          doc = doc_from_product(prod, batch_id)
          pid = doc["product_id"]
          if pid.nil? || pid.to_s.strip.empty?
            @skipped += 1
            return
          end

          doc_id = pid.to_s.strip
          buffer << {
            update: {
              _index: @index,
              _id: doc_id,
              data: { doc: doc, doc_as_upsert: true },
            },
          }
          flush(buffer) if buffer.size >= BATCH_SIZE
        end

        def doc_from_product(prod, batch_id)
          doc = prod.each_with_object({}) do |(k, v), acc|
            key = k.to_s
            next if key.empty?

            acc[key] = normalize_value(v)
          end
          doc["sync_batch_id"] = batch_id
          doc["synced_at"] = Time.now.utc.iso8601
          doc[@feed_field] = @feed_id unless @feed_id.empty?
          doc["source"] = @source_key if !@source_key.empty? && doc["source"].to_s.strip.empty?
          doc
        end

        def normalize_value(value)
          case value
          when Hash, Array then value
          when nil then nil
          else
            v = value.to_s
            v.strip.empty? && !value.is_a?(Numeric) ? nil : value
          end
        end

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
          fid = @feed_id
          fid = doc_feed_fallback if fid.empty?
          raise ArgumentError, "prune_obsolete needs feed_id or JSON source field" if fid.to_s.strip.empty?

          @sink.delete_by_query(index: @index, body: obsolete_feed_body(fid, batch_id))
        rescue StandardError => e
          @logger.warn do
            "prune_obsolete delete_by_query failed (bulk index succeeded): #{e.class}: #{e.message}"
          end
        end

        def doc_feed_fallback
          @source_key
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
