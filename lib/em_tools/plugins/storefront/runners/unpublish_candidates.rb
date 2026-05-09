# frozen_string_literal: true

require 'json'
require 'logger'
require 'time'

module EmTools
  module Plugins
    module Storefront
      module Runners
        # Iterates inventory rows in Elasticsearch (default +em_inventory+), batch-fetches each
        # row's enriched product document from the corresponding marketplace index
        # (default +amz_products_api_<mp>_v2+), runs every rule in
        # {EmTools::Core::Rules::Registry} (or the explicitly supplied subset) against the doc,
        # and bulk-indexes a record per failing product into the unpublish-candidates index
        # (default +em_products_to_unpublish+).
        #
        # The current scope is Amazon-sourced inventory (rows with +source+ matching +/^AMZ_/i+).
        # Other source families would need their own product-attribute index resolver; the
        # +product_index_resolver:+ hook below is how you wire them in.
        # rubocop:disable Metrics/ClassLength -- mirrors the Python pipeline surface end-to-end.
        class UnpublishCandidates
          DEFAULT_INVENTORY_INDEX = 'em_inventory'
          DEFAULT_UNPUBLISH_INDEX = 'em_products_to_unpublish'
          DEFAULT_BATCH_SIZE = 200
          AMZ_SOURCE_PATTERN = /\AAMZ_([A-Za-z]{2,})\z/

          attr_reader :stats

          # @param es_client [#mget, #search, #bulk, #refresh, #iterate_query, #index_exists?]
          # @param inventory_index [String]
          # @param unpublish_index [String] target index for failing products.
          # @param filters [Array<#check>] defaults to one instance of every rule in
          #   {EmTools::Core::Rules::Registry}.
          # @param product_index_resolver [#call] receives +source+ (e.g. +"AMZ_US"+), returns the
          #   ES index that holds enriched product docs (or +nil+ to skip that row family).
          # @param sources [Array<String>, nil] optional whitelist; defaults to all Amazon sources.
          # @param batch_size [Integer]
          # @param refresh [Boolean] refresh the unpublish index after the run.
          # @param max_evaluated [Integer, nil] hard cap on how many inventory rows to process
          #   (useful for smoke runs).
          # @param logger [Logger, nil]
          # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists -- explicit knobs make CLI/Rake plumbing readable
          def initialize(es_client:, inventory_index: DEFAULT_INVENTORY_INDEX,
                         unpublish_index: DEFAULT_UNPUBLISH_INDEX, filters: nil,
                         product_index_resolver: nil, sources: nil,
                         batch_size: DEFAULT_BATCH_SIZE, refresh: true,
                         max_evaluated: nil, logger: nil)
            @es = es_client
            @inventory_index = inventory_index
            @unpublish_index = unpublish_index
            @filters = filters || EmTools::Core::Rules::Registry.all
            @product_index_resolver = product_index_resolver || method(:default_product_index_for)
            @sources = Array(sources).map(&:to_s).reject(&:empty?).uniq
            @batch_size = [batch_size.to_i, 1].max
            @refresh = refresh
            @max_evaluated = max_evaluated&.to_i
            @logger = logger || EmTools::Core::Logger.for(progname: 'unpublish-candidates')
            reset_stats!
          end
          # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

          # Runs the full pipeline. Returns the +stats+ hash.
          def run!
            reset_stats!
            ensure_unpublish_index!

            group_inventory_rows_by_source.each do |source, rows|
              process_source(source, rows)
              break if max_evaluated_reached?
            end

            @es.refresh(@unpublish_index) if @refresh && @stats[:flagged].positive?
            @logger.info("[UnpublishCandidates] done: #{stats}")
            @stats
          end

          private

          def reset_stats!
            @stats = {
              inventory_scanned: 0,
              evaluated: 0,
              flagged: 0,
              missing_product_doc: 0,
              skipped_unsupported_source: 0,
              by_reason: Hash.new(0),
              by_source: Hash.new(0)
            }
          end

          def max_evaluated_reached?
            !@max_evaluated.nil? && @stats[:evaluated] >= @max_evaluated
          end

          def ensure_unpublish_index!
            return if @es.respond_to?(:index_exists?) && @es.index_exists?(@unpublish_index)
            return unless @es.respond_to?(:create_index)

            @es.create_index(@unpublish_index, body: { mappings: { properties: unpublish_index_properties } })
          rescue StandardError => e
            @logger.warn("[UnpublishCandidates] could not auto-create #{@unpublish_index}: #{e.class}: #{e.message}")
          end

          def unpublish_index_properties
            {
              product_id: { type: 'keyword' },
              source: { type: 'keyword' },
              source_product_id: { type: 'keyword' },
              marketplace: { type: 'keyword' },
              reason: { type: 'keyword' },
              message: { type: 'text' },
              evaluated_at: { type: 'date' }
            }
          end

          # Returns +{ "AMZ_US" => Enumerator<row>, ... }+. Inventory rows are iterated lazily
          # per-source via +iterate_query+ so we can batch +mget+ against the right product index.
          def group_inventory_rows_by_source
            sources_to_scan = @sources.empty? ? discover_amz_sources : @sources
            @logger.info("[UnpublishCandidates] sources=#{sources_to_scan.inspect}")

            sources_to_scan.each_with_object({}) do |source, h|
              h[source] = enum_for_source(source)
            end
          end

          def discover_amz_sources
            return [] unless @es.respond_to?(:search)

            resp = @es.search(
              index: @inventory_index,
              body: {
                size: 0,
                aggs: { sources: { terms: { field: 'source.keyword', size: 50 } } }
              }
            )
            buckets = resp.dig('aggregations', 'sources', 'buckets') || []
            buckets.map { |b| b['key'].to_s }.select { |s| AMZ_SOURCE_PATTERN.match?(s) }.sort
          end

          def enum_for_source(source)
            Enumerator.new do |y|
              @es.iterate_query(
                index: @inventory_index,
                query: { term: { 'source.keyword' => source } },
                max_hits: @max_evaluated
              ) do |hit|
                y << hit
              end
            end
          end

          # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
          def process_source(source, rows_enum)
            product_index = @product_index_resolver.call(source)
            unless product_index
              @logger.warn("[UnpublishCandidates] no product index for source=#{source}, skipping")
              rows_enum.each { @stats[:skipped_unsupported_source] += 1 }
              return
            end

            buffer = []
            rows_enum.each do |hit|
              @stats[:inventory_scanned] += 1
              src = hit['_source'] || {}
              asin = src['source_product_id'].to_s.strip.upcase
              next if asin.empty?

              buffer << { hit: hit, asin: asin }
              next unless buffer.size >= @batch_size

              evaluate_batch(source, product_index, buffer)
              buffer.clear
              break if max_evaluated_reached?
            end
            evaluate_batch(source, product_index, buffer) unless buffer.empty?
          end
          # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

          def evaluate_batch(source, product_index, buffer)
            asins = buffer.map { |entry| entry[:asin] }.uniq
            doc_by_asin = mget_products(product_index, asins)
            evaluated_at = Time.now.utc.iso8601
            failures = []
            buffer.each do |entry|
              break if max_evaluated_reached?

              record = evaluate_one(source, product_index, doc_by_asin, entry, evaluated_at)
              failures << record if record
            end
            bulk_index_failures(failures) unless failures.empty?
          end

          def evaluate_one(source, product_index, doc_by_asin, entry, evaluated_at)
            @stats[:evaluated] += 1
            row_src = entry[:hit]['_source'] || {}
            product_doc = doc_by_asin[entry[:asin]]
            return record_missing(source, row_src, entry[:asin], product_index, evaluated_at) if product_doc.nil?

            first_failure = run_filters(product_doc)
            return nil unless first_failure

            build_unpublish_record(source, row_src, entry[:asin],
                                   reason: first_failure[:reason],
                                   message: first_failure[:message],
                                   evaluated_at: evaluated_at)
          end

          def record_missing(source, row_src, asin, product_index, evaluated_at)
            @stats[:missing_product_doc] += 1
            build_unpublish_record(source, row_src, asin,
                                   reason: '[NotExist]',
                                   message: "no doc in #{product_index}",
                                   evaluated_at: evaluated_at)
          end

          # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          def mget_products(product_index, asins)
            return {} if asins.empty?
            return {} unless @es.respond_to?(:index_exists?) && @es.index_exists?(product_index)

            resp = @es.mget(index: product_index, ids: asins)
            (resp['docs'] || []).each_with_object({}) do |doc, h|
              next unless doc.is_a?(Hash) && doc['found']

              id = doc['_id'].to_s.strip.upcase
              h[id] = doc['_source'] || {}
            end
          end
          # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

          # Returns the first +{ reason:, message: }+ that fails, or +nil+ if all rules pass.
          def run_filters(product_doc)
            @filters.each do |filter|
              result = filter.check(product_doc)
              next if result[:passed] || result['passed']

              return {
                reason: result[:reason] || result['reason'],
                message: result[:message] || result['message'] || ''
              }
            end
            nil
          end

          # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
          def build_unpublish_record(source, row_src, asin, reason:, message:, evaluated_at:)
            mp = AMZ_SOURCE_PATTERN.match(source)&.captures&.first&.downcase
            doc_id = "#{source}::#{asin}"
            doc = {
              'product_id' => row_src['product_id'].to_s,
              'source' => source,
              'source_product_id' => asin,
              'marketplace' => mp,
              'reason' => reason,
              'message' => message,
              'evaluated_at' => evaluated_at
            }
            @stats[:flagged] += 1
            @stats[:by_reason][reason] += 1
            @stats[:by_source][source] += 1
            [{ 'index' => { '_index' => @unpublish_index, '_id' => doc_id } }, doc]
          end
          # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

          def bulk_index_failures(failures)
            body = failures.flat_map { |action_and_doc| action_and_doc }
            @es.bulk(body: body)
          end

          # Default Amazon resolver: +AMZ_US+ -> +amz_products_api_us_v2+, etc.
          def default_product_index_for(source)
            mp = AMZ_SOURCE_PATTERN.match(source)&.captures&.first
            return nil unless mp

            "amz_products_api_#{mp.downcase}_v2"
          end
        end
        # rubocop:enable Metrics/ClassLength
      end
    end
  end
end
