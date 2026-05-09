# frozen_string_literal: true

module EmTools
  module Core
    module Sinks
      # Implements the sink protocol expected by {EmTools::Core::Inventory::Sync}: +bulk(body:)+,
      # +refresh(index:)+, and +delete_by_query(index:, body:)+ when pruning.
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
          @client ||= EmTools::Clients::ElasticsearchClient.new
        end
      end
    end
  end
end
