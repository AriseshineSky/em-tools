# frozen_string_literal: true

module EmTools
  module Plugins
    module Kr
      module Sinks
        class PriceFreshnessSnapshot
          SNAPSHOT_KIND = "elevenst_price_freshness"

          class << self
            def index_name
              ENV.fetch("MONITORING_ELEVENST_PRICE_FRESHNESS_SNAPSHOT_INDEX",
                "monitoring_elevenst_price_freshness_snapshots")
            end

            def persist!(row, captured_at:, es_client:, refresh: nil)
              ensure_index!(es_client)
              captured_at = captured_at.utc
              do_refresh = refresh.nil? ? (ENV["MONITORING_ES_INDEX_REFRESH"] == "true") : refresh

              doc = {
                captured_at: captured_at.iso8601,
                snapshot_kind: SNAPSHOT_KIND,
              }.merge(normalize_for_json(row))

              es_client.index_document(
                index_name,
                body: doc,
                refresh: do_refresh,
              )
            end

            private

            def normalize_for_json(obj)
              case obj
              when Hash
                obj.each_with_object({}) do |(k, v), acc|
                  acc[k.to_s] = normalize_for_json(v)
                end
              when Array
                obj.map { |e| normalize_for_json(e) }
              else
                obj
              end
            end

            def ensure_index!(es_client)
              return if @snapshot_index_ready

              unless es_client.index_exists?(index_name)
                es_client.create_index(
                  index_name,
                  body: {
                    settings: { number_of_shards: 1, number_of_replicas: 1 },
                    mappings: {
                      properties: {
                        captured_at: { type: "date" },
                        snapshot_kind: { type: "keyword" },
                        data_source: { type: "keyword" },
                        inventory_index: { type: "keyword" },
                        products_index: { type: "keyword" },
                        fresh_threshold_days: { type: "integer" },
                      },
                    },
                  },
                )
              end
              @snapshot_index_ready = true
            rescue StandardError => e
              raise unless resource_conflict?(e)

              @snapshot_index_ready = true
            end

            def resource_conflict?(error)
              msg = error.message.to_s
              msg.include?("resource_already_exists_exception") ||
                msg.include?("already_exists") ||
                msg.include?("index_already_exists")
            end
          end
        end
      end
    end
  end
end
