# frozen_string_literal: true

require_relative '../clients/elasticsearch_client'

module Em
  module Tools
    # Implements the sink protocol expected by {InventorySync}: +bulk(body:)+, +refresh(index:)+,
    # and +delete_by_query(index:, body:)+ when pruning.
    class ElasticsearchBulkSink
      def initialize(client = nil)
        @client = client
      end

      def bulk(body:)
        client.bulk(body: body)
      end

      def refresh(index:)
        client.refresh(index)
      end

      def delete_by_query(index:, body:, **options)
        client.delete_by_query(index: index, body: body, **options)
      end

      private

      def client
        @client ||= Em::Clients::ElasticsearchClient.new
      end
    end
  end
end
