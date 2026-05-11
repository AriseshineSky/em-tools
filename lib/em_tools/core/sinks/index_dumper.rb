# frozen_string_literal: true

require "fileutils"
require "json"

module EmTools
  module Core
    module Sinks
      # Streams every hit from an Elasticsearch index to an NDJSON file (one full hit per line,
      # including +_id+ / +_source+). Replaces the duplicate "open client, iterate_all, write
      # NDJSON" body that used to live in two rake tasks.
      class IndexDumper
        DEFAULT_INDEX = "user1_lotteon_products"
        DEFAULT_BATCH_SIZE = 1000

        # @param es_client [#iterate_all]
        # @param index [String]
        # @param output_path [String, nil] when nil, +tmp/<index>.ndjson+ is used.
        # @param batch_size [Integer]
        # @param logger [::Logger, nil]
        def initialize(es_client:, index: DEFAULT_INDEX, output_path: nil,
          batch_size: DEFAULT_BATCH_SIZE, logger: nil)
          @es_client = es_client
          @index = index
          @output_path = output_path || File.join("tmp", "#{index}.ndjson")
          @batch_size = batch_size
          @logger = logger || EmTools::Core::Logger.for(progname: "es-dump")
        end

        # Builds a dumper from the standard +ES_DUMP_*+ env vars.
        #
        # @param env [Hash, ENV-like]
        # @param prefer_data_cluster [Boolean] when true, +DATA_ELASTICSEARCH_URL+ takes precedence
        #   over +ELASTICSEARCH_URL+. Used by +es-download-product+.
        def self.from_env(env: ENV, prefer_data_cluster: false)
          url = EmTools::Core::Config.elasticsearch_connection_url(prefer_data_cluster: prefer_data_cluster)
          new(
            es_client: EmTools::Clients::ElasticsearchClient.new(url: url),
            index: env.fetch("ES_DUMP_INDEX", DEFAULT_INDEX),
            output_path: env["ES_DUMP_OUTPUT"],
            batch_size: env.fetch("ES_DUMP_BATCH_SIZE", DEFAULT_BATCH_SIZE.to_s).to_i,
          )
        end

        # @return [EmTools::Core::Cli::Runner::Result]
        def run!
          ensure_output_dir!
          count = stream_hits!
          EmTools::Core::Cli::Runner::Result.new(summary: "Wrote #{count} hits to #{@output_path}")
        end

        private

        def ensure_output_dir!
          dir = File.dirname(@output_path)
          FileUtils.mkdir_p(dir) unless dir == "."
        end

        def stream_hits!
          count = 0
          File.open(@output_path, "w") do |out|
            @es_client.iterate_all(index: @index, batch_size: @batch_size) do |hit|
              out.puts(JSON.generate(hit))
              count += 1
            end
          end
          @logger.info { "[Dumped] index=#{@index} hits=#{count} -> #{@output_path}" }
          count
        end
      end
    end
  end
end
