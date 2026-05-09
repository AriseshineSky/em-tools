# frozen_string_literal: true

module EmTools
  module Plugins
    module Ebay
      module Pipelines
        # Orchestrates +ebay_listings:publish_snapshot+. Resolves the eBay product-id source
        # (inventory / seed_file / seed_dir / GCS in-memory), runs the coverage query for one
        # marketplace, sanity-checks the result, persists the snapshot.
        # rubocop:disable Metrics/ClassLength -- mirrors the rake task surface end to end.
        class PublishSnapshot
          # @param cli_marketplace [String, nil]
          # @param es_client [EmTools::Clients::ElasticsearchClient, nil]
          # @param env [Hash, ENV-like]
          # @param logger [::Logger, nil]
          # @param now [#call]
          def initialize(cli_marketplace: nil, es_client: nil, env: ENV, logger: nil, now: -> { Time.now.utc })
            @cli_marketplace = cli_marketplace
            @es_client = es_client || EmTools::Clients::ElasticsearchClient.new
            @env = env
            @logger = logger || EmTools::Core::Logger.for(progname: 'ebay-listings-snapshot')
            @now = now
          end

          # @return [EmTools::Core::RakeSupport::Result]
          def run!
            mp = resolve_marketplace
            query_opts = build_query_opts(mp)
            snapshot_time = @now.call
            row = run_query(query_opts, snapshot_time)
            validate_row!(row, query_opts)
            persist!(row, snapshot_time)

            EmTools::Core::RakeSupport::Result.new(
              summary: "Indexed eBay listings coverage snapshot (marketplace=#{mp.upcase}, " \
                       "index=#{row[:index_name]}) -> #{Sinks::CoverageSnapshot.index_name}"
            )
          end

          private

          def resolve_marketplace
            mp = @cli_marketplace.to_s.strip.downcase
            mp = @env['EBAY_LISTINGS_COVERAGE_MARKETPLACE'].to_s.strip.downcase if mp.empty?
            mp.empty? ? 'us' : mp
          end

          def inventory_mode?
            @env['EBAY_LISTINGS_COVERAGE_ID_SOURCE'].to_s.strip.casecmp?('inventory')
          end

          def seed_file
            @env['EBAY_LISTINGS_COVERAGE_SEED_FILE'].to_s.strip
          end

          def seed_dir
            @env['EBAY_LISTINGS_COVERAGE_SEED_DIR'].to_s.strip
          end

          def build_query_opts(marketplace)
            opts = { es_client: @es_client, marketplace: marketplace }
            return opts if inventory_mode?

            return require_seed_file!(opts) unless seed_file.empty?
            return require_seed_dir!(opts, marketplace) unless seed_dir.empty?

            configure_in_memory_gcs!(opts)
            opts
          end

          # +EBAY_LISTINGS_COVERAGE_SEED_FILE+ is consumed inside +ListingsCoverageQuery+ by reading
          # the same env var; we just validate the path here so the failure mode is fast + clear.
          def require_seed_file!(opts)
            path = File.expand_path(seed_file)
            unless File.file?(path)
              raise EmTools::Core::Errors::ConfigurationError,
                    "EBAY_LISTINGS_COVERAGE_SEED_FILE is not a file: #{path}"
            end

            opts
          end

          def require_seed_dir!(opts, marketplace)
            seed_dir_expanded = File.expand_path(seed_dir)
            path = File.join(seed_dir_expanded, "ebay_#{marketplace}.txt")
            unless File.file?(path)
              raise EmTools::Core::Errors::ConfigurationError,
                    "expected seed file #{path} under EBAY_LISTINGS_COVERAGE_SEED_DIR"
            end

            opts[:seed_dir] = seed_dir_expanded
            opts
          end

          def configure_in_memory_gcs!(opts)
            creds_path = EmTools::Clients::GcsServiceAccountPath.require!(
              env: @env, missing_message: missing_gcs_message
            )
            bucket = @env.fetch('GCS_BUCKET', 'em-bucket')
            prefix = @env.fetch('GCS_SEEDS_PREFIX', 'em-analytics').sub(%r{/+\z}, '')
            gcs = EmTools::Clients::GcsHelper.new(creds_path, bucket, prefix)
            opts[:seed_text_fetcher] = ->(mkt) { gcs.download_string("#{prefix}/sources/EBAY_#{mkt.upcase}.txt") }
          end

          def missing_gcs_message
            creds_path = EmTools::Clients::GcsServiceAccountPath.resolve
            'set EBAY_LISTINGS_COVERAGE_SEED_DIR (ebay_<mp>.txt), EBAY_LISTINGS_COVERAGE_SEED_FILE, or ' \
              'EBAY_LISTINGS_COVERAGE_ID_SOURCE=inventory, or place a GCS JSON key at ' \
              "#{creds_path}, or set GCS_SERVICE_ACCOUNT_PATH"
          end

          def run_query(query_opts, snapshot_time)
            Queries::ListingsCoverageQuery.new(**query_opts.merge(snapshot_time: snapshot_time)).fetch_row
          end

          def validate_row!(row, query_opts)
            err = row[:error] || row['error']
            unless err.nil? || err.to_s.strip.empty?
              raise EmTools::Core::Errors::EmptyResultError, "EbayListingsCoverageQuery failed: #{err}"
            end
            return if seed_source_skips_validation?(query_opts)

            loaded = (row[:seed_ids_loaded] || row['seed_ids_loaded']).to_i
            return if loaded.positive?

            raise EmTools::Core::Errors::EmptyResultError, empty_loaded_message(row, query_opts)
          end

          def seed_source_skips_validation?(query_opts)
            !inventory_mode? && !query_opts[:seed_dir] && !query_opts[:seed_text_fetcher] && seed_file.empty?
          end

          def empty_loaded_message(row, query_opts)
            return inventory_empty_message(row) if inventory_mode?

            'no seed product ids loaded. Check EBAY_LISTINGS_COVERAGE_SEED_DIR / SEED_FILE / GCS EBAY_*.txt ' \
              'and that lines are tab-separated JSON with source_product_id in column 2.' \
              "[seed_dir=#{query_opts[:seed_dir].inspect}]"
          end

          def inventory_empty_message(row)
            idx = row[:inventory_index] || row['inventory_index'] || @env['EBAY_LISTINGS_COVERAGE_INVENTORY_INDEX']
            "no eBay product ids loaded from inventory (inventory_index=#{idx.inspect}). " \
              'Check EBAY_LISTINGS_COVERAGE_INVENTORY_SOURCE_TERMS, ' \
              'EBAY_LISTINGS_COVERAGE_INVENTORY_PRODUCT_ID_FIELD, ' \
              'and optional EBAY_LISTINGS_COVERAGE_INVENTORY_MARKETPLACE_FIELD.'
          end

          def persist!(row, snapshot_time)
            Sinks::CoverageSnapshot.persist!([row], captured_at: snapshot_time, es_client: @es_client, refresh: true)
          end
        end
        # rubocop:enable Metrics/ClassLength
      end
    end
  end
end
