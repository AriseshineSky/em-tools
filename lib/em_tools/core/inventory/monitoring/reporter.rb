# frozen_string_literal: true

module EmTools
  module Core
    module Inventory
      module Monitoring
        # Reports inventory sync progress to monitoring-dashboard.
        class Reporter
          def initialize(client: nil, env: ENV, logger: nil)
            @client = client || EmTools::Core::Monitoring::Client.from_env(env)
            @logger = logger
          end

          def report_running(source:, gs_uri: nil, meta: {})
            post(
              source: source,
              status: "running",
              gs_uri: gs_uri,
              message: "sync started",
              meta: meta,
            )
          end

          def report_done(source:, gs_uri: nil, docs_indexed: 0, docs_deleted: 0, duration_ms: nil, meta: {})
            post(
              source: source,
              status: "done",
              gs_uri: gs_uri,
              docs_indexed: docs_indexed,
              docs_deleted: docs_deleted,
              message: "sync complete",
              meta: meta.merge(duration_ms: duration_ms).compact,
            )
          end

          def report_error(source:, gs_uri: nil, message:, duration_ms: nil, meta: {})
            post(
              source: source,
              status: "error",
              gs_uri: gs_uri,
              message: message,
              meta: meta.merge(duration_ms: duration_ms).compact,
            )
          end

          private

          def post(attrs)
            return unless @client.configured?

            @client.post_inventory_sync_run(
              attrs.merge(run_on: Date.today.iso8601),
            )
          rescue StandardError => e
            @logger&.warn { "[InventorySyncMonitor] report failed: #{e.class}: #{e.message}" }
            nil
          end
        end
      end
    end
  end
end
