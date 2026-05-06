# frozen_string_literal: true

module Em
  module Tools
    module Cli
      class App
        COMMANDS = {
          'dump' => Commands::Dump,
          'import-products' => Commands::ImportProducts,
          'uploadable-product-filter' => Commands::UploadableProductFilter,
          'amz-upload-products-from-es' => Commands::AmzUploadProductsFromEs,
          'amz-uploadable-products-formatter-from-file' => Commands::AmzUploadableProductsFormatterFromFile,
          'asin-products-to-es' => Commands::AsinProductsToEs
        }.freeze

        def self.start(argv)
          new(argv).start
        end

        def initialize(argv)
          @argv = argv.dup
        end

        def start
          command = @argv.shift
          if command.nil? || command.start_with?('-')
            usage_main
            exit 1
          end

          klass = COMMANDS[command]
          unless klass
            warn "error: unknown command: #{command}"
            usage_main
            exit 1
          end

          klass.new.run(@argv)
        end

        def usage_main
          warn <<~MSG
            Usage:
              em-tools dump INDEX [options]
              em-tools import-products [options] INPUT_PATH
              em-tools uploadable-product-filter [options]
              em-tools amz-upload-products-from-es [options]
              em-tools amz-uploadable-products-formatter-from-file [options] PRODUCTS_PATH
              em-tools asin-products-to-es [options]

            Commands:
              dump                          Stream Elasticsearch docs as NDJSON.
              import-products               Filter products and emit import batch plans as NDJSON.
              uploadable-product-filter     Stream Amazon ASINs from ES (detailed stream flags).
              amz-upload-products-from-es   Celery-compatible entry (-m/-i/-t); ASIN stream + price rules config.
              amz-uploadable-products-formatter-from-file  ASIN file -> ES mget product+offer -> uploadable NDJSON (+ sidecars).
              asin-products-to-es           ASIN index -> product mget -> filters -> bulk to sink ES index.
          MSG
        end
      end
    end
  end
end
