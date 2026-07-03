# frozen_string_literal: true

module EmTools
  module Plugins
    module Kr
      module Pipelines
        # Query stale/missing 11ST inventory products and schedule ``elevenst`` jobs on Scrapyd.
        class ScheduleStaleInventoryRecrawl
          DEFAULT_SPIDER = "elevenst"
          DEFAULT_BATCH_SIZE = 25

          def initialize(
            data_es_client: nil,
            scrapyd_client: nil,
            env: ENV,
            logger: nil,
            now: -> { Time.now.utc },
            **query_opts
          )
            @data_es_client = data_es_client || EmTools::Core::Config.elasticsearch_client(cluster: "data")
            @scrapyd_client = scrapyd_client || EmTools::Clients::ScrapydClient.from_env(env)
            @env = env
            @logger = logger || EmTools::Core::Logger.for(progname: "elevenst-recrawl")
            @now = now
            @query_opts = query_opts
            @spider = pick(query_opts.delete(:spider), "ELEVENST_RECRAWL_SPIDER", DEFAULT_SPIDER)
            @batch_size = resolve_batch_size(query_opts.delete(:batch_size))
            @dry_run = truthy?(query_opts.delete(:dry_run))
            @st11_category_filter = pick(
              query_opts.delete(:st11_category_filter),
              "ELEVENST_RECRAWL_ST11_CATEGORY_FILTER",
              "0",
            )
            @skip_existing = pick(
              query_opts.delete(:skip_existing),
              "ELEVENST_RECRAWL_SKIP_EXISTING",
              "0",
            )
          end

          def run!
            stats = Queries::StaleInventoryRecrawlQuery.new(
              es_client: @data_es_client,
              snapshot_time: @now.call,
              **@query_opts,
            ).fetch

            err = stats[:error] || stats["error"]
            raise EmTools::Core::Errors::EmptyResultError, "StaleInventoryRecrawlQuery failed: #{err}" if err

            items = Array(stats[:recrawl_items])
            if items.empty?
              return EmTools::Core::Cli::Runner::Result.new(
                summary: "No stale/missing elevenst products to recrawl " \
                  "(inventory=#{stats[:inventory_total]}, fresh=#{stats[:fresh_products]})",
              )
            end

            scheduled_jobs = schedule_items!(items)
            EmTools::Core::Cli::Runner::Result.new(
              summary: build_summary(stats, scheduled_jobs),
            )
          end

          private

          def schedule_items!(items)
            return [] if @dry_run

            unless @scrapyd_client.configured?
              raise EmTools::Core::Errors::ConfigurationError,
                "SCRAPYD_URL and SCRAPYD_PROJECT must be set to schedule recrawls"
            end

            daemon = @scrapyd_client.daemon_status
            @logger.info(
              "scrapyd node=#{daemon['node_name']} pending=#{daemon['pending']} running=#{daemon['running']}",
            )

            jobs = []
            items.each_slice(@batch_size) do |batch|
              urls = batch.map(&:url).join(",")
              response = @scrapyd_client.schedule_spider(
                spider: @spider,
                settings: {
                  urls: urls,
                  skip_existing: @skip_existing,
                  st11_category_filter: @st11_category_filter,
                },
              )
              status = response["status"].to_s
              unless status == "ok"
                raise EmTools::Core::Errors::ConfigurationError,
                  "scrapyd schedule failed: #{response['message'] || response.inspect}"
              end

              job_id = response["jobid"].to_s
              jobs << {
                jobid: job_id,
                urls: batch.size,
              }
              @logger.info("scheduled #{@spider} job=#{job_id} urls=#{batch.size}")
            end
            jobs
          end

          def build_summary(stats, scheduled_jobs)
            items = Array(stats[:recrawl_items])
            parts = [
              (@dry_run ? "Dry-run:" : "Scheduled"),
              "#{items.size} URL(s)",
              "missing=#{stats[:missing_products]}",
              "stale=#{stats[:stale_products]}",
              "fresh=#{stats[:fresh_products]}",
              "inventory=#{stats[:inventory_total]}",
              "stale_days=#{stats[:stale_days]}",
              "field=#{stats[:time_field]}",
            ]
            unless @dry_run
              parts << "jobs=#{scheduled_jobs.size}"
              parts << "scrapyd=#{@scrapyd_client.instance_variable_get(:@base_url)}"
            end
            parts.join(" ")
          end

          def pick(cli_value, env_key, default = nil)
            raw = cli_value.to_s.strip
            raw = @env[env_key].to_s.strip if raw.empty?
            raw = default.to_s if raw.empty? && default
            raw
          end

          def resolve_batch_size(cli_value)
            raw = cli_value.to_s.strip
            raw = @env["ELEVENST_RECRAWL_BATCH_SIZE"].to_s.strip if raw.empty?
            raw = DEFAULT_BATCH_SIZE.to_s if raw.empty?
            size = Integer(raw)
            raise EmTools::Core::Errors::ConfigurationError, "batch-size must be > 0" unless size.positive?

            size
          rescue ArgumentError
            raise EmTools::Core::Errors::ConfigurationError,
              "batch-size must be a positive integer (got #{raw.inspect})"
          end

          def truthy?(value)
            %w[1 true yes on].include?(value.to_s.strip.downcase)
          end
        end
      end
    end
  end
end
