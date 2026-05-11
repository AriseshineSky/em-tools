# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonLowestOffer
      module Pipelines
        # Orchestrates +lowest_offer:publish_snapshot+ end to end so the rake task itself stays a
        # one-liner. Picks the ASIN source mode (ES inventory / GCS in-memory / local seed_dir),
        # runs {Queries::ListingsCoverageQuery}, sanity-checks the rows, and persists the snapshot
        # via {Sinks::CoverageSnapshot}. # -- mirrors the rake task surface end to end.
        class PublishSnapshot
          # @param cli_marketplaces [String, nil] comma-separated marketplaces from rake CLI args
          #   (e.g. +"us,ca"+). Empty / nil means "use the default list".
          # @param es_client [EmTools::Clients::ElasticsearchClient, nil]
          # @param env [Hash, ENV-like]
          # @param logger [::Logger, nil]
          # @param now [#call] override for {Time.now} in tests.
          def initialize(cli_marketplaces: nil, es_client: nil, env: ENV, logger: nil, now: -> { Time.now.utc })
            @cli_marketplaces = cli_marketplaces
            @es_client = es_client || EmTools::Clients::ElasticsearchClient.new
            @env = env
            @logger = logger || EmTools::Core::Logger.for(progname: "lowest-offer-snapshot")
            @now = now
          end

          # @return [EmTools::Core::Cli::Runner::Result]
          def run!
            query_opts = build_query_opts
            apply_cli_marketplaces!(query_opts)

            snapshot_time = @now.call
            rows = run_query(query_opts, snapshot_time)
            validate_rows!(rows, query_opts)
            persist!(rows, snapshot_time)

            EmTools::Core::Cli::Runner::Result.new(summary: summary_line(rows, query_opts))
          end

          private

          def inventory_mode?
            @env["LOWEST_OFFER_ID_SOURCE"].to_s.strip.casecmp?("inventory")
          end

          def build_query_opts
            opts = { es_client: @es_client }
            return opts if inventory_mode?

            seed_dir = @env["LOWEST_OFFER_SEED_DIR"].to_s.strip
            seed_dir.empty? ? configure_in_memory_gcs!(opts) : configure_seed_dir!(opts, seed_dir)
            opts
          end

          # Mode A: no seed dir → stream each marketplace's AMZ_<MP>.txt from GCS in memory.
          def configure_in_memory_gcs!(opts)
            creds_path = EmTools::Clients::GcsServiceAccountPath.require!(
              env: @env, missing_message: missing_creds_message,
            )
            bucket = @env.fetch("GCS_BUCKET", "em-bucket")
            prefix = @env.fetch("GCS_SEEDS_PREFIX", "em-analytics").sub(%r{/+\z}, "")
            gcs = EmTools::Clients::GcsHelper.new(creds_path, bucket, prefix)
            opts[:seed_text_fetcher] = ->(mp) { gcs.download_string("#{prefix}/sources/AMZ_#{mp.upcase}.txt") }
          end

          # Mode B: local seed_dir → ensure each marketplace has an +amz_<mp>.txt+, downloading
          # from GCS (or re-downloading when +LOWEST_OFFER_SEEDS_FORCE_DOWNLOAD=1+) on miss.
          def configure_seed_dir!(opts, seed_dir)
            seed_dir_expanded = File.expand_path(seed_dir)
            marketplaces = Queries::ListingsCoverageQuery.marketplaces_for_publish(@cli_marketplaces)
            force = @env["LOWEST_OFFER_SEEDS_FORCE_DOWNLOAD"] == "1"
            if needs_seed_sync?(seed_dir_expanded, marketplaces, force)
              sync_missing_seeds!(seed_dir_expanded, marketplaces, force)
            end
            opts[:seed_dir] = seed_dir_expanded
          end

          def needs_seed_sync?(seed_dir, marketplaces, force)
            force || marketplaces.any? { |mp| !Sources::SeedFiles.seed_file_present?(seed_dir, mp) }
          end

          # -- 6-arg sync call + creds-resolve are one atomic step.
          def sync_missing_seeds!(seed_dir, marketplaces, force)
            creds_path = EmTools::Clients::GcsServiceAccountPath.require!(
              env: @env, missing_message: missing_seeds_message,
            )
            bucket = @env.fetch("GCS_BUCKET", "em-bucket")
            prefix = @env.fetch("GCS_SEEDS_PREFIX", "em-analytics")
            @logger.info { "[SeedSync] dir=#{seed_dir} marketplaces=#{marketplaces.join(",")} force=#{force}" }
            Sources::SeedFiles.sync_from_gcs(
              seed_dir,
              marketplaces: marketplaces,
              creds_path: creds_path,
              bucket: bucket,
              prefix: prefix,
              force: force,
            )
          end
          # rubocop:enable Metrics/MethodLength

          def missing_creds_message
            creds_path = EmTools::Clients::GcsServiceAccountPath.resolve
            "set LOWEST_OFFER_SEED_DIR to a directory with amz_<mp>.txt seeds, or put a GCS JSON key at " \
              "#{creds_path}, or set GCS_SERVICE_ACCOUNT_PATH to load AMZ_*.txt from GCS in memory"
          end

          def missing_seeds_message
            creds_path = EmTools::Clients::GcsServiceAccountPath.resolve
            "missing seed files under LOWEST_OFFER_SEED_DIR; place a GCS JSON key at " \
              "#{creds_path} or set GCS_SERVICE_ACCOUNT_PATH to pull AMZ_<MP>.txt from GCS " \
              "(or unset LOWEST_OFFER_SEED_DIR for in-memory GCS). " \
              "LOWEST_OFFER_SEEDS_FORCE_DOWNLOAD=1 overwrites existing amz_<mp>.txt."
          end

          def apply_cli_marketplaces!(opts)
            cli_mps = @cli_marketplaces.to_s.split(",").map(&:strip).reject(&:empty?).map(&:downcase)
            opts[:marketplaces] = cli_mps if cli_mps.any?
          end

          def run_query(query_opts, snapshot_time)
            Queries::ListingsCoverageQuery.new(**query_opts.merge(snapshot_time: snapshot_time)).fetch_all
          end

          def validate_rows!(rows, query_opts)
            return validate_inventory_rows!(rows) if inventory_mode?

            validate_seed_dir_rows!(rows, query_opts[:seed_dir]) if query_opts[:seed_dir]
            # in-memory GCS mode: empty results are reflected as +row[:error]+ already; nothing to do.
          end

          def validate_inventory_rows!(rows)
            rows.each do |row|
              next if row_has_error?(row) || row_loaded(row).positive?

              idx = row_field(row, :inventory_index) || @env["LOWEST_OFFER_INVENTORY_INDEX"]
              raise EmTools::Core::Errors::EmptyResultError,
                "no Amazon ASINs loaded from em_inventory for #{row_field(row, :marketplace)} " \
                  "(inventory_index=#{idx.inspect}, seed_asins_loaded=#{row_loaded(row)}). " \
                  "Check LOWEST_OFFER_INVENTORY_AMAZON_SOURCES, LOWEST_OFFER_INVENTORY_PRODUCT_ID_FIELD, " \
                  "and optional LOWEST_OFFER_INVENTORY_MARKETPLACE_FIELD."
            end
          end

          def validate_seed_dir_rows!(rows, seed_dir)
            rows.each do |row|
              next if row_has_error?(row) || row_loaded(row).positive?

              mp = row_field(row, :marketplace).to_s.downcase
              raise EmTools::Core::Errors::EmptyResultError,
                "no seed ASINs loaded for #{row_field(row, :marketplace)} " \
                  "(seed_file_present=#{row_field(row, :seed_file_present).inspect}, " \
                  "seed_asins_loaded=#{row_loaded(row)}). " \
                  "Check #{seed_dir} contains amz_#{mp}.txt or ebay_<mp>.txt (tab + JSON column 2)."
            end
          end

          def row_has_error?(row)
            err = row_field(row, :error)
            !err.nil? && !err.to_s.strip.empty?
          end

          def row_loaded(row)
            row_field(row, :seed_asins_loaded).to_i
          end

          def row_field(row, key)
            row[key] || row[key.to_s]
          end

          def persist!(rows, snapshot_time)
            Sinks::CoverageSnapshot.persist!(rows, captured_at: snapshot_time, es_client: @es_client, refresh: true)
          end

          def summary_line(rows, query_opts)
            label = if query_opts[:marketplaces]
              query_opts[:marketplaces].join(",")
            elsif @env["LOWEST_OFFER_MARKETPLACES"].to_s.strip.empty?
              "default list"
            else
              @env["LOWEST_OFFER_MARKETPLACES"].strip
            end
            "Indexed #{rows.size} marketplace row(s) (#{label}) -> #{Sinks::CoverageSnapshot.index_name}"
          end
        end
        # rubocop:enable Metrics/ClassLength
      end
    end
  end
end
