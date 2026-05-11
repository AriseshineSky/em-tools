# frozen_string_literal: true

require "fileutils"
require "json"

module EmTools
  module Core
    module Sinks
      # Streams every hit from an Elasticsearch index to an NDJSON file.
      #
      # Optional +policy+ is a predicate object that decides whether a document is allowed
      # through. The contract is intentionally tiny:
      #
      #   policy.blocked?(source)        # required, returns Boolean
      #   policy.matched(source)         # optional, returns Array<String> for the side-file
      #   policy.blocked_record(source,  # optional, returns the Hash to write per-rejection
      #     id: hit_id)
      #   policy.keyword_count           # optional, surfaces "X blacklist keyword(s)" in the summary
      #
      # When the policy provides them, +blocked_output_path+ becomes useful: each rejected
      # document is appended as one NDJSON line so callers can audit *which* products were
      # skipped and *why*.
      class IndexDumper
        DEFAULT_INDEX = "user1_lotteon_products"
        DEFAULT_BATCH_SIZE = 1000

        # Lightweight result struct returned alongside +Cli::Runner::Result+ when callers want
        # the raw counts (e.g. for tests or downstream metrics).
        Counts = Data.define(:total, :written, :blocked) do
          def to_summary(output_path:, blocked_output_path: nil, keyword_count: nil)
            parts = ["Wrote #{written} hits to #{output_path}"]
            if blocked.positive? || keyword_count
              tail = "blocked #{blocked}/#{total}"
              tail += " against #{keyword_count} blacklist keyword(s)" if keyword_count
              tail += " -> #{blocked_output_path}" if blocked_output_path && blocked.positive?
              parts << tail
            end
            parts.join("; ")
          end
        end

        # @param es_client [#iterate_all]
        # @param index [String]
        # @param output_path [String, nil] when nil, +tmp/<index>.ndjson+ is used.
        # @param batch_size [Integer]
        # @param policy [#blocked?, nil]              predicate object; nil disables policy checks.
        # @param blocked_output_path [String, nil]    side-file for rejected docs (NDJSON).
        # @param logger [::Logger, nil]
        def initialize(es_client:, index: DEFAULT_INDEX, output_path: nil,
          batch_size: DEFAULT_BATCH_SIZE, policy: nil, blocked_output_path: nil, logger: nil)
          @es_client = es_client
          @index = index
          @output_path = output_path || File.join("tmp", "#{index}.ndjson")
          @batch_size = batch_size
          @policy = policy
          @blocked_output_path = blocked_output_path
          @logger = logger || EmTools::Core::Logger.for(progname: "es-dump")
        end

        # Builds a dumper from the standard +ES_DUMP_*+ env vars. Extra +**opts+ flow straight
        # through to {.new}, so callers can layer in a +policy:+ / +blocked_output_path:+ etc.
        #
        # @param env [Hash, ENV-like]
        # @param prefer_data_cluster [Boolean] when true, +DATA_ELASTICSEARCH_URL+ takes precedence
        #   over +ELASTICSEARCH_URL+. Used by +es-download-product+.
        def self.from_env(env: ENV, prefer_data_cluster: false, **opts)
          url = EmTools::Core::Config.elasticsearch_connection_url(prefer_data_cluster: prefer_data_cluster)
          new(
            es_client: EmTools::Clients::ElasticsearchClient.new(url: url),
            index: env.fetch("ES_DUMP_INDEX", DEFAULT_INDEX),
            output_path: env["ES_DUMP_OUTPUT"],
            batch_size: env.fetch("ES_DUMP_BATCH_SIZE", DEFAULT_BATCH_SIZE.to_s).to_i,
            **opts,
          )
        end

        # @return [EmTools::Core::Cli::Runner::Result]
        def run!
          ensure_output_dir!
          counts = stream_hits!
          summary = counts.to_summary(
            output_path: @output_path,
            blocked_output_path: @blocked_output_path,
            keyword_count: policy_keyword_count,
          )
          EmTools::Core::Cli::Runner::Result.new(summary: summary)
        end

        private

        def policy_keyword_count
          @policy.keyword_count if @policy.respond_to?(:keyword_count)
        end

        def ensure_output_dir!
          [@output_path, @blocked_output_path].compact.each do |path|
            dir = File.dirname(path)
            FileUtils.mkdir_p(dir) unless dir == "."
          end
        end

        def stream_hits!
          total = written = blocked = 0

          File.open(@output_path, "w") do |out|
            with_blocked_io do |blocked_io|
              @es_client.iterate_all(index: @index, batch_size: @batch_size) do |hit|
                total += 1
                source = hit["_source"]
                if @policy&.blocked?(source)
                  blocked += 1
                  record_blocked(blocked_io, hit)
                else
                  out.puts(JSON.generate(source))
                  written += 1
                end
              end
            end
          end

          @logger.info do
            "[Dumped] index=#{@index} total=#{total} written=#{written} blocked=#{blocked} -> #{@output_path}"
          end
          Counts.new(total: total, written: written, blocked: blocked)
        end

        def with_blocked_io(&block)
          if @blocked_output_path && @policy
            File.open(@blocked_output_path, "w", &block)
          else
            block.call(nil)
          end
        end

        def record_blocked(blocked_io, hit)
          return unless blocked_io
          return unless @policy.respond_to?(:matched)

          source = hit["_source"] || {}
          record =
            if @policy.respond_to?(:blocked_record)
              @policy.blocked_record(source, id: hit["_id"])
            else
              {
                "_id" => hit["_id"],
                "title" => source["title"],
                "brand" => source["brand"],
                "matched" => @policy.matched(source),
              }
            end
          blocked_io.puts(JSON.generate(record))
        end
      end
    end
  end
end
