# frozen_string_literal: true

require 'elasticsearch'

module EmTools
  module Clients
    # rubocop:disable Metrics/ClassLength
    class ElasticsearchClient
      attr_reader :client

      # @param url [String, nil] override cluster URL; nil uses {EmTools::Core::Config.elasticsearch_url}.
      # @param logger [Logger, nil] optional override; defaults to {EmTools::Core::Logger.for}.
      def initialize(url: nil, logger: nil)
        resolved = url.to_s.strip
        resolved = EmTools::Core::Config.elasticsearch_url if resolved.empty?
        args = EmTools::Core::Config.elasticsearch_client_arguments(url: resolved).merge(url: resolved)
        @client = ::Elasticsearch::Client.new(args)
        @logger = logger || EmTools::Core::Logger.for(progname: 'es-client')
        @url = resolved
      end

      # ---- Index APIs ----

      # Create an index with optional settings and mappings
      def create_index(index, body: {}, **options)
        client.indices.create(index: index, body: body, **sanitize_api_options(options))
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def iterate_all(index:, batch_size: 1000, &block)
        pit_id = nil
        pit = client.open_point_in_time(index: index, keep_alive: '1m')
        pit_id = pit['id']

        response = client.search(
          body: {
            size: batch_size,
            pit: { id: pit_id, keep_alive: '1m' },
            sort: [{ _shard_doc: 'asc' }],
            query: { match_all: {} }
          }
        )

        loop do
          hits = response['hits']['hits']
          break if hits.empty?

          hits.each(&block)

          response = client.search(
            body: {
              size: batch_size,
              pit: { id: pit_id, keep_alive: '1m' },
              sort: [{ _shard_doc: 'asc' }],
              search_after: hits.last['sort'],
              query: { match_all: {} }
            }
          )
        end
      ensure
        client.close_point_in_time(body: { id: pit_id }) if pit_id
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # Point-in-time scan with a custom +query+ (same transport pattern as +iterate_all+).
      # Optional +max_hits+ stops after that many documents yielded.
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def iterate_query(index:, query:, batch_size: 1000, sort: [{ _shard_doc: 'asc' }], max_hits: nil, &block)
        pit_id = nil
        yielded = 0
        pit = client.open_point_in_time(index: index, keep_alive: '1m')
        pit_id = pit['id']

        response = client.search(
          body: {
            size: batch_size,
            pit: { id: pit_id, keep_alive: '1m' },
            sort: sort,
            query: query
          }
        )

        loop do
          hits = response['hits']['hits']
          break if hits.empty?

          hits.each do |hit|
            block.call(hit)
            yielded += 1
            return yielded if max_hits && yielded >= max_hits
          end

          response = client.search(
            body: {
              size: batch_size,
              pit: { id: pit_id, keep_alive: '1m' },
              sort: sort,
              search_after: hits.last['sort'],
              query: query
            }
          )
        end
        yielded
      ensure
        client.close_point_in_time(body: { id: pit_id }) if pit_id
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # Delete an index
      def delete_index(index, **options)
        client.indices.delete(index: index, **sanitize_api_options(options))
      end

      # Check if an index exists
      def index_exists?(index, **options)
        client.indices.exists(index: index, **sanitize_api_options(options))
      end

      # Get index settings
      def get_index_settings(index, **options)
        client.indices.get_settings(index: index, **sanitize_api_options(options))
      end

      # Get index mappings
      def get_mappings(index, **options)
        client.indices.get_mapping(index: index, **sanitize_api_options(options))
      end

      # Put mappings on an existing index
      def put_mappings(index, body:, **options)
        client.indices.put_mapping(index: index, body: body, **sanitize_api_options(options))
      end

      # Refresh one or more indices
      def refresh(index = '_all', **options)
        client.indices.refresh(index: index, **sanitize_api_options(options))
      end

      # ---- Document APIs ----

      # Index a document (create or update)
      def index_document(index, body:, id: nil, **options)
        client.index(index: index, id: id, body: body, **sanitize_api_options(options))
      end

      # Get a document by id
      def get_document(index, id, **options)
        client.get(index: index, id: id, **sanitize_api_options(options))
      end

      # Delete a document by id
      def delete_document(index, id, **options)
        client.delete(index: index, id: id, **sanitize_api_options(options))
      end

      # Update a document by id
      def update_document(index, id, body:, **options)
        client.update(index: index, id: id, body: body, **sanitize_api_options(options))
      end

      # Bulk index documents. Logs a sample of item-level errors at WARN when ES reports
      # +response['errors']+ — the raw response is still returned so callers can decide whether to
      # raise.
      def bulk(body:, **options)
        response = client.bulk(body: body, **sanitize_api_options(options))
        log_bulk_errors!(response, body) if response.is_a?(Hash) && response['errors']
        response
      end

      # Delete documents matching a query (e.g. prune stale inventory rows per feed).
      def delete_by_query(index:, body:, **options)
        client.delete_by_query(index: index, body: body, **sanitize_api_options(options))
      end

      # ---- Search APIs ----

      # Search with a query body
      def search(body:, index: nil, **options)
        params = {}
        params[:index] = index if index
        params[:body] = body
        params.merge!(sanitize_api_options(options))
        client.search(**params)
      end

      # Multi-get documents by +_id+ from a single index (batch product lookup by ASIN).
      def mget(index:, ids:, **options)
        id_list = Array(ids).map(&:to_s).map(&:strip).reject(&:empty?)
        return { 'docs' => [] } if id_list.empty?

        client.mget(index: index, body: { ids: id_list }, **sanitize_api_options(options))
      end

      # Count documents matching a query
      def count(index: nil, body: nil, **options)
        params = {}
        params[:index] = index if index
        params[:body] = body if body
        params.merge!(sanitize_api_options(options))
        client.count(**params)
      end

      # ---- Cluster APIs ----

      # Get cluster health
      def cluster_health(**options)
        client.cluster.health(**sanitize_api_options(options))
      end

      # Get cluster stats
      def cluster_stats(**options)
        client.cluster.stats(**sanitize_api_options(options))
      end

      # Get node info
      def nodes_info(**options)
        client.nodes.info(**sanitize_api_options(options))
      end

      # ---- Scroll APIs ----

      # Open a scroll search
      def scroll(scroll_id:, scroll: '1m', **options)
        client.scroll(scroll_id: scroll_id, scroll: scroll, **sanitize_api_options(options))
      end

      # Clear a scroll
      def clear_scroll(scroll_id:, **options)
        client.clear_scroll(scroll_id: scroll_id, **sanitize_api_options(options))
      end

      # ---- Reindex ----
      def reindex(body:, **options)
        client.reindex(body: body, **sanitize_api_options(options))
      end

      # ---- Task Management ----
      def tasks_get(task_id:, **options)
        client.tasks.get(task_id: task_id, **sanitize_api_options(options))
      end

      private

      # elasticsearch-api validates URL/query params; :request_timeout is not allowed there.
      def sanitize_api_options(options)
        return {} if options.nil? || options.empty?

        options.reject { |k, _| k.to_sym == :request_timeout }
      end

      # rubocop:disable Metrics/AbcSize -- response shape forces multi-step extraction
      def log_bulk_errors!(response, body)
        items = Array(response['items'])
        bad = items.filter_map { |item| item.values.first if item.values.first['error'] }
        return if bad.empty?

        sample = bad.first(3).map do |item|
          err = item['error'] || {}
          "_id=#{item['_id']} status=#{item['status']} type=#{err['type']} reason=#{err['reason']}"
        end
        @logger&.warn do
          "[BulkErrors] failed=#{bad.size}/#{items.size} actions=#{body.size} sample=#{sample.inspect}"
        end
      end
      # rubocop:enable Metrics/AbcSize
    end
    # rubocop:enable Metrics/ClassLength
  end
end
