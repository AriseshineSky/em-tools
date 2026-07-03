# frozen_string_literal: true

require "csv"
require "fileutils"

module EmTools
  module Plugins
    module Kr
      module Pipelines
        class ExportMissingInventoryCrawl
          DEFAULT_SPIDER = "elevenst"
          DEFAULT_BATCH_SIZE = 25
          TSV_HEADERS = %w[source source_product_id source_product_url crawl_url].freeze

          def initialize(
            data_es_client: nil,
            scrapyd_client: nil,
            env: ENV,
            logger: nil,
            **query_opts
          )
            @data_es_client = data_es_client || EmTools::Core::Config.elasticsearch_client(cluster: "data")
            @scrapyd_client = scrapyd_client || EmTools::Clients::ScrapydClient.from_env(env)
            @env = env
            @logger = logger || EmTools::Core::Logger.for(progname: "elevenst-missing-crawl")
            @query_opts = query_opts
            @output_path = pick(query_opts.delete(:output_path), "ELEVENST_MISSING_CRAWL_OUTPUT", nil)
            @schedule = truthy?(query_opts.delete(:schedule))
            @dry_run = truthy?(query_opts.delete(:dry_run))
            @spider = pick(query_opts.delete(:spider), "ELEVENST_MISSING_CRAWL_SPIDER", DEFAULT_SPIDER)
            @batch_size = resolve_batch_size(query_opts.delete(:batch_size))
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
            stats = Queries::MissingInventoryCrawlQuery.new(
              es_client: @data_es_client,
              **@query_opts,
            ).fetch

            err = stats[:error]
            raise EmTools::Core::Errors::EmptyResultError, "MissingInventoryCrawlQuery failed: #{err}" if err

            rows = Array(stats[:rows])
            path = write_rows!(rows)
            scheduled_jobs = @schedule ? schedule_rows!(rows) : []

            EmTools::Core::Cli::Runner::Result.new(
              summary: build_summary(stats, path, scheduled_jobs),
            )
          end

          private

          def write_rows!(rows)
            path = resolve_output_path
            FileUtils.mkdir_p(File.dirname(path))

            CSV.open(path, "w", col_sep: "\t", write_headers: true, headers: TSV_HEADERS) do |csv|
              rows.each do |row|
                csv << [
                  row.source,
                  row.source_product_id,
                  row.source_product_url,
                  row.crawl_url,
                ]
              end
            end

            @logger.info("wrote missing crawl export path=#{path} rows=#{rows.size}")
            path
          end

          def resolve_output_path
            raw = @output_path.to_s.strip
            raw = @env["ELEVENST_MISSING_CRAWL_OUTPUT"].to_s.strip if raw.empty?
            return raw unless raw.empty?

            stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
            File.expand_path("log/elevenst-missing-crawl-#{stamp}.tsv", Dir.pwd)
          end

          def schedule_rows!(rows)
            return [] if rows.empty?
            return [] if @dry_run

            unless @scrapyd_client.configured?
              raise EmTools::Core::Errors::ConfigurationError,
                "SCRAPYD_URL and SCRAPYD_PROJECT must be set to schedule missing crawls"
            end

            daemon = @scrapyd_client.daemon_status
            @logger.info(
              "scrapyd node=#{daemon['node_name']} pending=#{daemon['pending']} running=#{daemon['running']}",
            )

            jobs = []
            rows.each_slice(@batch_size) do |batch|
              urls = batch.map(&:crawl_url).join(",")
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
              jobs << { jobid: job_id, urls: batch.size }
              @logger.info("scheduled #{@spider} job=#{job_id} urls=#{batch.size}")
            end
            jobs
          end

          def build_summary(stats, path, scheduled_jobs)
            parts = [
              "Exported #{Array(stats[:rows]).size} missing crawl row(s)",
              "inventory=#{stats[:inventory_total]}",
              "found=#{stats[:products_found]}",
              "missing=#{stats[:missing_products]}",
              "file=#{path}",
            ]
            if @schedule
              parts << (@dry_run ? "schedule=dry-run" : "jobs=#{scheduled_jobs.size}")
              parts << "scrapyd=#{@scrapyd_client.instance_variable_get(:@base_url)}" unless @dry_run
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
