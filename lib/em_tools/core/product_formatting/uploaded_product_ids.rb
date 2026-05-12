# frozen_string_literal: true

require "csv"
require "set"
require "tempfile"

module EmTools
  module Core
    module ProductFormatting
      # Ruby port of +em_tasks/contexts/product_formatting/product_filter.py::get_uploaded_source_product_ids+.
      #
      # Asks Spree (the storefront API) which +SourceProductID+s have already been
      # uploaded for a given +source+ (e.g. +"AMZ_US"+, +"LOTTEON"+) by triggering
      # the +inventory_reports/download+ CSV export, then collects the IDs into a
      # +Set+. Producers can then skip products already on the storefront.
      #
      # The Python helper accepted bare endpoint / api_key / api_version triples
      # and instantiated a +SpreeApi+ inside. The Ruby version takes a constructed
      # {EmTools::Clients::SpreeClient} (dependency injection) and exposes a
      # {.from_env} convenience constructor for callers that want the legacy
      # "build the client from env vars" behavior.
      class UploadedProductIds
        SOURCE_PRODUCT_ID_COLUMN = "SourceProductID"
        DEFAULT_FILE_PREFIX = "inventory"

        # Build from +SPREE_*+ env vars. Returns +nil+ when endpoint or api key is
        # missing so callers can skip-with-warning instead of blowing up.
        def self.from_env(env: ENV, file_prefix: DEFAULT_FILE_PREFIX, logger: nil)
          endpoint = env["SPREE_ENDPOINT"]
          api_key = env["SPREE_API_KEY"]
          return if endpoint.to_s.strip.empty? || api_key.to_s.strip.empty?

          client = EmTools::Clients::SpreeClient.new(
            endpoint,
            api_key,
            api_version: env.fetch("SPREE_API_VERSION", "v1"),
            logger: logger,
          )
          new(client: client, file_prefix: file_prefix, logger: logger)
        end

        # @param client [EmTools::Clients::SpreeClient, nil]
        # @param file_prefix [String] passed through to +Tempfile+.
        # @param logger [::Logger, nil]
        def initialize(client:, file_prefix: DEFAULT_FILE_PREFIX, logger: nil)
          @client = client
          @file_prefix = file_prefix.to_s
          @logger = logger || EmTools::Core::Logger.for(progname: "uploaded-product-ids")
        end

        # @param source [String] storefront +source+ identifier (e.g. +"AMZ_US"+).
        # @return [Set<String>] empty when the client is missing or download yields no rows.
        def fetch(source)
          unless client_ready?
            @logger&.warn { "Skipping uploaded-product filtering: Spree endpoint/api key missing." }
            return Set.new
          end

          ids = download_and_collect(source)
          @logger&.info { "Loaded #{ids.size} uploaded product IDs from inventory" }
          ids
        end

        private

        def client_ready?
          @client && !@client.endpoint.to_s.empty? && !@client.api_key.to_s.empty?
        end

        def download_and_collect(source)
          # Block form auto-deletes the file on exit (success or raise).
          Tempfile.create(["#{@file_prefix}_", ".csv"]) do |tmp|
            tmp.close
            @client.download_inventory(source, tmp.path)
            File.file?(tmp.path) ? load_ids(tmp.path) : Set.new
          end
        end

        def load_ids(path)
          # Match Python's +errors="ignore"+: storefront CSVs occasionally contain
          # mojibake we don't want to abort on. Read raw bytes, then +scrub+ drops
          # any invalid UTF-8 sequence before CSV ever sees it.
          content = File.read(path, mode: "rb").force_encoding(Encoding::UTF_8).scrub("")

          ids = Set.new
          CSV.parse(content, headers: true) do |row|
            id = row[SOURCE_PRODUCT_ID_COLUMN].to_s.strip
            ids << id unless id.empty?
          end
          ids
        end
      end
    end
  end
end
