# frozen_string_literal: true

module EmTools
  module Plugins
    module Kr
      module Pipelines
        class PublishPriceFreshnessSnapshot
          def initialize(data_es_client: nil, es_client: nil, env: ENV, logger: nil, now: -> { Time.now.utc }, **query_opts)
            @data_es_client = data_es_client || EmTools::Core::Config.elasticsearch_client(cluster: "data")
            @es_client = es_client || EmTools::Clients::ElasticsearchClient.new
            @env = env
            @logger = logger || EmTools::Core::Logger.for(progname: "elevenst-price-freshness")
            @now = now
            @query_opts = query_opts
          end

          def run!
            snapshot_time = @now.call
            row = Queries::PriceFreshnessQuery.new(
              es_client: @data_es_client,
              snapshot_time: snapshot_time,
              **@query_opts,
            ).fetch_row
            validate_row!(row)
            persist!(row, snapshot_time)

            EmTools::Core::Cli::Runner::Result.new(
              summary: "Indexed 11ST price freshness snapshot " \
                "(inventory=#{row[:inventory_total]}, found=#{row[:products_found]}, " \
                "fresh<=#{row[:fresh_threshold_days]}d=#{row[:fresh_within_threshold]}, " \
                "stale=#{row[:stale_older_than_threshold]}) " \
                "-> #{Sinks::PriceFreshnessSnapshot.index_name}",
            )
          end

          private

          def validate_row!(row)
            err = row[:error] || row["error"]
            return if err.nil? || err.to_s.strip.empty?

            raise EmTools::Core::Errors::EmptyResultError, "PriceFreshnessQuery failed: #{err}"
          end

          def persist!(row, snapshot_time)
            Sinks::PriceFreshnessSnapshot.persist!(
              row,
              captured_at: snapshot_time,
              es_client: @es_client,
              refresh: true,
            )
          end
        end
      end
    end
  end
end
