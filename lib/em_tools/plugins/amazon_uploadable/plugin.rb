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
        EmTools::Core::PluginRegistry.register(:amazon_uploadable, self)

        # Shorter prefix than the auto-derived "amazon-uploadable"; kept consistent with the
        # historical +amz-*+ naming so the alias map below stays small.
        def self.cli_namespace
          "amz-uploadable"
        end

        def cli_commands
          {
            "amz-uploadable:filter" => Cli::UploadableProductFilter,
            "amz-uploadable:upload-from-es" => Cli::AmzUploadProductsFromEs,
            "amz-uploadable:format-from-file" => Cli::AmzUploadableProductsFormatterFromFile,
            "amz-uploadable:asin-to-es" => Cli::AsinProductsToEs,
          }
        end

        # No engine-level filters/transforms/source/sink: the work happens inside cohesive
        # operations, exposed as factory helpers for direct calls.
        def uploadable_product_filter(**opts)
          Filters::UploadableProductFilter.new(**opts)
        end

        def asin_product_pipeline(**opts)
          Pipelines::AsinProductIndexPipeline.new(**opts)
        end

        def upload_runner(**opts)
          Pipelines::UploadProductsFromEs::Runner.new(**opts)
        end

        def products_formatter(**opts)
          Formatters::UploadableProductsFormatterFromFile.new(**opts)
        end

        def price_calculator(**opts)
          Transforms::PriceCalculator.new(**opts)
        end
      end
    end
  end
end
