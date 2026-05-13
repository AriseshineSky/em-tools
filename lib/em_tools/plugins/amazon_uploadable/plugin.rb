# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonUploadable
      # Bundles the Amazon "uploadable products" workflow:
      #   ASIN extraction (UploadableProductFilter) -> ASIN product index pipeline ->
      #   Amazon upload runner.
      #
      # The actual filter/transform classes are heavyweight, multi-step operations and do not slot
      # cleanly into EmTools::Core::PipelineEngine's per-record filter/transform model. They are exposed
      # as "operations" via the convenience helpers below; callers and the CLI invoke them
      # directly (see `cli_commands` for the wired CLI commands).
      class Plugin < EmTools::Core::Plugin::Base
        def self.plugin_name = :amazon_uploadable

        EmTools::Core::PluginRegistry.register(plugin_name, self)

        def capabilities
          {
            uploadable: {
              filter: Filters::UploadableProductFilter,
              pipeline: Pipelines::AsinProductIndexPipeline,
              runner: Pipelines::UploadProductsFromEs::Runner,
              formatter: Formatters::UploadableProductsFormatterFromFile,
              price_calculator: Transforms::PriceCalculator,
              build_feed: Operations::BuildUploadableFeed,
            },
            sources: {
              file_asins: Sources::FileAsins,
              es_asins: Sources::EsAsins,
            },
            sinks: {
              feed_es: Sinks::UploadableFeedEs,
            },
          }
        end

        def dependencies
          @dependencies ||= {
            es_client: EmTools::Clients::ElasticsearchClient.new,
            logger: EmTools::Core::Logger.for(progname: "amz-uploadable"),
          }
        end

        # Shorter prefix than the auto-derived "amazon-uploadable".
        def self.cli_namespace
          "amz-uploadable"
        end

        def cli_commands
          {
            "filter" => Cli::UploadableProductFilter,
            "upload-from-es" => Cli::AmzUploadProductsFromEs,
            "build-feed" => Cli::BuildUploadableFeed,
            "format-from-file" => Cli::AmzUploadableProductsFormatterFromFile,
            "asin-to-es" => Cli::AsinProductsToEs,
          }
        end

        # No engine-level filters/transforms/source/sink: the work happens inside cohesive
        # operations, exposed as factory helpers for direct calls.
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

        private

        def blank?(value)
          value.nil? || value.to_s.strip.empty?
        end
      end
    end
  end
end
