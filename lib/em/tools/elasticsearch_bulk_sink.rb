# frozen_string_literal: true

require_relative '../clients/elasticsearch_client'

module Em
  module Tools
    # Implements the bulk sink protocol expected by {InventorySync}: +bulk(body:)+ and +refresh(index:)+.
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

      private

      def client
        @client ||= Em::Clients::ElasticsearchClient.new
      end
    end
  end
end
