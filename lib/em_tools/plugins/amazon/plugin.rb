# frozen_string_literal: true

module EmTools
  module Plugins
    module Amazon
      # Unified Amazon plugin: **uploadable** workflows (ASIN filter, product index, upload runner)
      # and **lowest-offer** coverage snapshot pipelines. Registered as +:amazon+; CLI namespace +amazon+.
      class Plugin < EmTools::Core::Plugin::Base
        def self.plugin_name = :amazon

        EmTools::Core::PluginRegistry.register(plugin_name, self)

        def capabilities
          {
            uploadable: {
              filter: Uploadable::Filters::UploadableProductFilter,
              pipeline: Uploadable::Pipelines::AsinProductIndexPipeline,
              runner: Uploadable::Pipelines::UploadProductsFromEs::Runner,
              formatter: Uploadable::Formatters::UploadableProductsFormatterFromFile,
              price_calculator: Uploadable::Transforms::PriceCalculator,
              build_feed: Uploadable::Operations::BuildUploadableFeed,
            },
            coverage: {
              listings_query: LowestOffer::Queries::ListingsCoverageQuery,
              assessment: LowestOffer::Queries::CoverageAssessment,
              snapshot: LowestOffer::Sinks::CoverageSnapshot,
              publish_snapshot: LowestOffer::Pipelines::PublishSnapshot,
              download_and_publish: LowestOffer::Pipelines::DownloadAndPublish,
            },
            sources: {
              file_asins: Uploadable::Sources::FileAsins,
              es_asins: Uploadable::Sources::EsAsins,
              seed_files: LowestOffer::Sources::SeedFiles,
              inventory_asin_loader: LowestOffer::Sources::InventoryAsinLoader,
            },
            sinks: {
              feed_es: Uploadable::Sinks::UploadableFeedEs,
            },
            services: {
              offer_service: LowestOffer::Services::OfferService,
            },
            filters: {
              offer_filter: LowestOffer::Filters::OfferFilter,
            },
            patterns: {
              asin: LowestOffer::Patterns::AsinPattern,
            },
          }
        end

        def dependencies
          @dependencies ||= {
            es_client: EmTools::Clients::ElasticsearchClient.new,
            logger: EmTools::Core::Logger.for(progname: "amazon"),
          }
        end

        def self.cli_namespace
          "amazon"
        end

        def cli_commands
          {
            "products filter" => Uploadable::Cli::UploadableProductFilter,
            "products upload-from-es" => Uploadable::Cli::AmzUploadProductsFromEs,
            "products build-feed" => Uploadable::Cli::BuildUploadableFeed,
            "products format-file" => Uploadable::Cli::AmzUploadableProductsFormatterFromFile,
            "products index-asins" => Uploadable::Cli::AsinProductsToEs,
            "coverage publish-snapshot" => LowestOffer::Cli::PublishSnapshot,
            "coverage download-and-publish" => LowestOffer::Cli::DownloadAndPublish,
          }
        end

        def uploadable_product_filter(**opts)
          capabilities.dig(:uploadable, :filter).new(**opts)
        end

        def asin_product_pipeline(**opts)
          capabilities.dig(:uploadable, :pipeline).new(**opts)
        end

        def upload_runner(**opts)
          capabilities.dig(:uploadable, :runner).new(**opts)
        end

        def uploadable_asin_source(kind:, marketplace:, path: nil, index: nil, max_asins: nil, dry_run: false, **filter_opts)
          case kind.to_s
          when "file"
            raise EmTools::Core::Errors::ConfigurationError, "--seed-path is required for --seed-source=file" if blank?(path)

            capabilities.dig(:sources, :file_asins).new(path: path, max_asins: max_asins)
          when "es"
            capabilities.dig(:sources, :es_asins).new(
              client: dry_run ? nil : dependencies[:es_client],
              marketplace: marketplace,
              index: index,
              max_asins: max_asins,
              **filter_opts,
            )
          else
            raise EmTools::Core::Errors::ConfigurationError, "unknown seed source: #{kind.inspect} (expected es|file)"
          end
        end

        def uploadable_feed_sink(output_path: nil, sink_index: nil, bulk_chunk: 500, refresh: false, dry_run: false)
          sinks = []
          sinks << EmTools::Core::Sinks::JsonlFile.new(path: output_path) unless blank?(output_path)
          unless blank?(sink_index)
            sinks << capabilities.dig(:sinks, :feed_es).new(
              client: dry_run ? nil : dependencies[:es_client],
              index: sink_index,
              batch_size: bulk_chunk,
              refresh: refresh,
            )
          end
          sinks << EmTools::Core::Sinks::StdoutJsonl.new if sinks.empty?
          EmTools::Core::Sinks::Composite.new(sinks: sinks)
        end

        def build_uploadable_feed(client: nil, dry_run: false, **opts)
          client ||= dependencies[:es_client] unless dry_run
          capabilities.dig(:uploadable, :build_feed).new(
            client: client,
            dry_run: dry_run,
            logger: dependencies[:logger],
            **opts,
          )
        end

        def products_formatter(**opts)
          capabilities.dig(:uploadable, :formatter).new(**opts)
        end

        def price_calculator(**opts)
          capabilities.dig(:uploadable, :price_calculator).new(**opts)
        end

        def listings_coverage_query(**opts)
          args = opts.dup
          es_client = args.delete(:es_client) || dependencies[:es_client]
          capabilities.dig(:coverage, :listings_query).new(es_client: es_client, **args)
        end

        def coverage_assessment(**opts)
          args = opts.dup
          search_client = args.delete(:search_client) || dependencies[:es_client]
          capabilities.dig(:coverage, :assessment).new(search_client: search_client, **args)
        end

        def seed_files(**_opts)
          capabilities.dig(:sources, :seed_files)
        end

        def inventory_asin_loader(**opts)
          args = opts.dup
          es_client = args.delete(:es_client) || dependencies[:es_client]
          capabilities.dig(:sources, :inventory_asin_loader).new(es_client: es_client, **args)
        end

        def coverage_snapshot(**_opts)
          capabilities.dig(:coverage, :snapshot)
        end

        def asin_pattern(**_opts)
          capabilities.dig(:patterns, :asin)
        end

        def offer_service(**opts)
          args = opts.dup
          client = args.delete(:client) || dependencies[:es_client]
          capabilities.dig(:services, :offer_service).new(client: client, **args)
        end

        def offer_filter(**opts)
          capabilities.dig(:filters, :offer_filter).new(**opts)
        end

        def publish_snapshot(**opts)
          args = opts.dup
          es_client = args.delete(:es_client) || dependencies[:es_client]
          logger = args.delete(:logger) || dependencies[:logger]
          capabilities.dig(:coverage, :publish_snapshot).new(es_client: es_client, logger: logger, **args)
        end

        def download_and_publish(**opts)
          capabilities.dig(:coverage, :download_and_publish).new(**opts)
        end

        private

        def blank?(value)
          value.nil? || value.to_s.strip.empty?
        end
      end
    end
  end
end
