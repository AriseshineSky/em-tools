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

        def products_formatter(**opts)
          capabilities.dig(:uploadable, :formatter).new(**opts)
        end

        def price_calculator(**opts)
          capabilities.dig(:uploadable, :price_calculator).new(**opts)
        end
      end
    end
  end
end
