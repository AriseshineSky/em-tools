# frozen_string_literal: true

require 'elasticsearch'

module Em
  module Tools
    class ElasticsearchClient
      attr_reader :client

      # request_timeout is a transport option for ::Elasticsearch::Client, not a REST query param;
      # passing it to #search / #index raises ArgumentError from elasticsearch-api param validation.
      DEFAULT_REQUEST_TIMEOUT = 120

      def initialize(request_timeout: nil)
        @client = ::Elasticsearch::Client.new(
          url: ENV['ELASTICSEARCH_URL']
        )
      end

      # ---- Index APIs ----

      # Create an index with optional settings and mappings
      def create_index(index, body: {}, **options)
        client.indices.create(index: index, body: body, **options)
      end

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

      # Delete an index
      def delete_index(index, **options)
        client.indices.delete(index: index, **options)
      end

      # Check if an index exists
      def index_exists?(index, **options)
        client.indices.exists(index: index, **options)
      end

      # Get index settings
      def get_index_settings(index, **options)
        client.indices.get_settings(index: index, **options)
      end

      # Get index mappings
      def get_mappings(index, **options)
        client.indices.get_mapping(index: index, **options)
      end

      # Put mappings on an existing index
      def put_mappings(index, body:, **options)
        client.indices.put_mapping(index: index, body: body, **options)
      end

      # Refresh one or more indices
      def refresh(index = '_all', **options)
        client.indices.refresh(index: index, **options)
      end

      # ---- Document APIs ----

      # Index a document (create or update)
      def index_document(index, body:, id: nil, **options)
        client.index(index: index, id: id, body: body, **options)
      end

      # Get a document by id
      def get_document(index, id, **options)
        client.get(index: index, id: id, **options)
      end

      # Delete a document by id
      def delete_document(index, id, **options)
        client.delete(index: index, id: id, **options)
      end

      # Update a document by id
      def update_document(index, id, body:, **options)
        client.update(index: index, id: id, body: body, **options)
      end

      # Bulk index documents
      def bulk(body:, **options)
        client.bulk(body: body, **options)
      end

      # ---- Search APIs ----

      # Search with a query body
      def search(body:, index: nil, **options)
        params = {}
        params[:index] = index if index
        params[:body] = body
        params.merge!(options)
        client.search(**params)
      end

      # Count documents matching a query
      def count(index: nil, body: nil, **options)
        params = {}
        params[:index] = index if index
        params[:body] = body if body
        params.merge!(options)
        client.count(**params)
      end

      # ---- Cluster APIs ----

      # Get cluster health
      def cluster_health(**options)
        client.cluster.health(**options)
      end

      # Get cluster stats
      def cluster_stats(**options)
        client.cluster.stats(**options)
      end

      # Get node info
      def nodes_info(**options)
        client.nodes.info(**options)
      end

      # ---- Scroll APIs ----

      # Open a scroll search
      def scroll(scroll_id:, scroll: '1m', **options)
        client.scroll(scroll_id: scroll_id, scroll: scroll, **options)
      end

      # Clear a scroll
      def clear_scroll(scroll_id:, **options)
        client.clear_scroll(scroll_id: scroll_id, **options)
      end

      # ---- Reindex ----
      def reindex(body:, **options)
        client.reindex(body: body, **options)
      end

      # ---- Task Management ----
      def tasks_get(task_id:, **options)
        client.tasks.get(task_id: task_id, **options)
      end
    end
  end
end
