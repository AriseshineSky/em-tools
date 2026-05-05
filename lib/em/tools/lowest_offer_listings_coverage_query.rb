# frozen_string_literal: true

module Em
  module Tools
    # Same behaviour as monitoring-dashboard LowestOfferListingsCoverageQuery (no Rails).
    class LowestOfferListingsCoverageQuery
      DEFAULT_MARKETPLACES = %w[us ca mx ae de in it jp uk].freeze

      def initialize(es_client:, marketplaces: nil, time_field: nil)
        @es_client = es_client
        @marketplaces = if marketplaces&.any?
                          marketplaces.map { |m| m.to_s.downcase }
                        else
                          env_list = parse_marketplace_list(ENV['LOWEST_OFFER_MARKETPLACES'])
                          env_list.empty? ? DEFAULT_MARKETPLACES : env_list
                        end
        tf = time_field.to_s.strip
        @time_field = tf.empty? ? ENV.fetch('LOWEST_OFFER_TIME_FIELD', 'time') : tf
      end

      def fetch_all
        @marketplaces.map { |mp| fetch_marketplace(mp.to_s.downcase) }
      end

      def fetch_marketplace(mp)
        index = "lowest_offer_listings_#{mp}_new"
        row = base_row(mp, index)
        activity = search_activity(index)
        row.merge(activity)
      rescue StandardError => e
        warn "LowestOfferListingsCoverageQuery failed for #{index}: #{e.class} #{e.message}"
        base_row(mp, index).merge(empty_activity).merge(error: e.message.to_s.byteslice(0, 200))
      end

      private

      def parse_marketplace_list(raw)
        return DEFAULT_MARKETPLACES if raw.nil? || raw.to_s.strip.empty?

        raw.split(',').map(&:strip).reject(&:empty?).map(&:downcase)
      end

      def base_row(mp, index)
        {
          marketplace: mp.upcase,
          index_name: index
        }
      end
      def search_activity(index)
        body = {
          timeout: '60s',
          size: 0,
          track_total_hits: true,
          query: { match_all: {} },
          aggs: {
            missing_time: {
              filter: {
                bool: {
                  must_not: { exists: { field: @time_field } }
                }
              }
            },
            with_time: {
              filter: { exists: { field: @time_field } },
              aggs: {
                windows: {
                  filters: {
                    filters: {
                      last_24h: time_range('now-24h', 'now'),
                      hours_24_to_48_ago: time_range('now-48h', 'now-24h'),
                      hours_48_to_72_ago: time_range('now-72h', 'now-48h'),
                      older_than_72h: {
                        bool: {
                          must: [
                            { exists: { field: @time_field } },
                            { range: { @time_field => { lt: 'now-72h' } } }
                          ]
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        response = @es_client.search(index: index, body: body)
        parse_activity(response)
      end

      def time_range(gte, lt)
        {
          bool: {
            must: [
              { exists: { field: @time_field } },
              { range: { @time_field => { gte: gte, lt: lt } } }
            ]
          }
        }
      end

      def parse_activity(response)
        total = extract_total_hits(response)
        buckets = response.dig('aggregations', 'with_time', 'windows', 'buckets') || {}
        missing = response.dig('aggregations', 'missing_time', 'doc_count').to_i

        {
          total_docs: total,
          time_last_24h: bucket_count(buckets, 'last_24h'),
          time_24_to_48h_ago: bucket_count(buckets, 'hours_24_to_48_ago'),
          time_48_to_72h_ago: bucket_count(buckets, 'hours_48_to_72_ago'),
          time_older_than_72h: bucket_count(buckets, 'older_than_72h'),
          docs_missing_time: missing
        }
      end

      def extract_total_hits(response)
        raw = response.dig('hits', 'total')
        return raw.to_i if raw.is_a?(Numeric)
        return raw.to_i if raw.is_a?(String)
        return raw['value'].to_i if raw.is_a?(Hash)

        0
      end

      def bucket_count(buckets, key)
        b = buckets[key]
        return 0 unless b

        b['doc_count'].to_i
      end

      def empty_activity
        {
          total_docs: 0,
          time_last_24h: 0,
          time_24_to_48h_ago: 0,
          time_48_to_72h_ago: 0,
          time_older_than_72h: 0,
          docs_missing_time: 0
        }
      end
    end
  end
end
