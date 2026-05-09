# frozen_string_literal: true

require 'uri'

module EmTools
  module Core
    class Config
      def self.reload!
        @settings = nil
        @gcs = nil
      end

      def self.settings
        @settings ||= SettingsLoader.load
      end

      def self.elasticsearch_url
        first = string_present(ENV['ELASTICSEARCH_URL']) ||
                dig_string(settings, %w[elasticsearch url])
        return first if first

        raise 'ELASTICSEARCH_URL missing (set in .env or settings YAML elasticsearch.url; ' \
              'see examples/config/settings.example.yml)'
      end

      # Options merged into +Elasticsearch::Client.new+ (basic auth or API key).
      #
      # When +url+ already contains credentials (+http://user:pass@host+), returns +{}+ so global
      # +ELASTICSEARCH_*+ env does not override the second cluster (+DATA_ELASTICSEARCH_URL+, etc.).
      #
      # When +url+ has no embedded credentials, optional +ELASTICSEARCH_API_KEY+ or
      # +ELASTICSEARCH_USERNAME+ / +ELASTICSEARCH_PASSWORD+ apply (primary cluster).
      def self.elasticsearch_client_arguments(url: nil)
        target = string_present(url.to_s)
        return {} if target && url_has_embedded_credentials?(target)

        api_key = string_present(ENV['ELASTICSEARCH_API_KEY'])
        if api_key
          { api_key: api_key }
        else
          user = string_present(ENV['ELASTICSEARCH_USERNAME'])
          password = string_present(ENV['ELASTICSEARCH_PASSWORD'])
          args = {}
          args[:user] = user if user
          args[:password] = password if password
          args
        end
      end

      # +explicit+ (e.g. +ES_DUMP_ELASTICSEARCH_URL+) wins; then optional data/analytics cluster from
      # +DATA_ELASTICSEARCH_URL+ when +prefer_data_cluster+ is true; otherwise {elasticsearch_url}.
      def self.elasticsearch_connection_url(explicit: nil, prefer_data_cluster: false)
        direct = string_present(explicit)
        return direct if direct

        if prefer_data_cluster
          data_elasticsearch_url || elasticsearch_url
        else
          elasticsearch_url
        end
      end

      # Named ES URLs: +ELASTICSEARCH_CLUSTER_<NAME>_URL+ (NAME uppercased, +\-+ -> +_+), then
      # +DATA_ELASTICSEARCH_URL+ for cluster names +data+ and +analytics+, then settings YAML
      # (+elasticsearch_clusters.<name>.url+).
      def self.elasticsearch_cluster_url(name)
        n = name.to_s
        pfx = "ELASTICSEARCH_CLUSTER_#{n.upcase.tr('-', '_')}_URL"
        u = string_present(ENV[pfx])
        return u if u

        if %w[data analytics].include?(n)
          u = string_present(ENV['DATA_ELASTICSEARCH_URL'])
          return u if u
        end

        clusters = settings['elasticsearch_clusters']
        return nil unless clusters.is_a?(Hash)

        node = clusters[n]
        return nil unless node.is_a?(Hash)

        string_present(node['url'])
      end

      # Optional second cluster (convenience); same as +DATA_ELASTICSEARCH_URL+ env or YAML +data+ cluster.
      def self.data_elasticsearch_url
        string_present(ENV['DATA_ELASTICSEARCH_URL']) ||
          elasticsearch_cluster_url('data') ||
          elasticsearch_cluster_url('analytics')
      end

      # Per-exporter ES URL from +exporters.<key>+: optional +url+, or +cluster+ (name in +elasticsearch_clusters+).
      # Lotteon defaults to the data cluster (+DATA_ELASTICSEARCH_URL+) when YAML has no exporter entry.
      def self.exporter_elasticsearch_url(exporter_key)
        key = exporter_key.to_s
        cfg = exporter_entry(key)

        unless cfg.nil?
          direct = string_present(cfg['url'])
          return direct if direct

          cluster = string_present(cfg['cluster'])
          if cluster
            resolved = elasticsearch_cluster_url(cluster)
            return resolved if resolved
          end
        end

        lotteon_fallback_elasticsearch_url(key)
      end

      # Index name for an exporter (+exporters.<key>.index+), or +fallback_index+ when unset.
      def self.exporter_index(exporter_key, fallback_index)
        cfg = exporter_entry(exporter_key.to_s)
        return fallback_index if cfg.nil?

        string_present(cfg['index']) || fallback_index
      end

      def self.redis_url
        string_present(ENV['REDIS_URL']) || dig_string(settings, %w[redis url])
      end

      def self.blacklist_api_endpoint
        string_present(ENV['BLACKLIST_API_ENDPOINT']) ||
          dig_string(settings, %w[blacklist_api endpoint])
      end

      def self.blacklist_api_path
        string_present(ENV['BLACKLIST_API_PATH']) ||
          dig_string(settings, %w[blacklist_api path])
      end

      def self.blacklist_api_key
        string_present(ENV['BLACKLIST_API_KEY']) ||
          dig_string(settings, %w[blacklist_api api_key])
      end

      def self.blacklist_api_token
        string_present(ENV['BLACKLIST_API_TOKEN']) ||
          dig_string(settings, %w[blacklist_api api_token]) ||
          blacklist_api_key
      end

      # Path to a GCS service account JSON key (optional; used by gcs rake tasks /
      # +EmTools::Clients::GcsHelper+). When +GCS_SERVICE_ACCOUNT_PATH+ is unset, defaults to
      # +~/.em_celery/gcs-sa.json+.
      def self.gcs_service_account_path
        EmTools::Clients::GcsServiceAccountPath.resolve
      end

      # Per-site HTTP settings from +sites.<name>+ in settings.yml, overridden by
      # +EM_TOOLS_SITE_<NAME>_ENDPOINT+, +_BASE_URL+, +_TOKEN+ (NAME is upcased, +-+ -> +_+).
      # rubocop:disable Metrics/AbcSize -- small merge of three keys from YAML vs ENV.
      def self.site(name)
        key = name.to_s
        sites = settings['sites']
        y = sites.is_a?(Hash) ? sites[key] : nil
        y = {} unless y.is_a?(Hash)
        pfx = SettingsLoader.site_env_prefix(key)
        {
          'base_url' => string_present(ENV["#{pfx}BASE_URL"]) || dig_string(y, %w[base_url]),
          'endpoint' => string_present(ENV["#{pfx}ENDPOINT"]) || dig_string(y, %w[endpoint]),
          'token' => string_present(ENV["#{pfx}TOKEN"]) || dig_string(y, %w[token])
        }.compact
      end
      # rubocop:enable Metrics/AbcSize

      def self.gcs
        @gcs ||= Gcs.new
      end

      def self.string_present(str)
        s = str.to_s.strip
        s.empty? ? nil : s
      end

      def self.dig_string(hash, keys)
        v = hash&.dig(*keys.map(&:to_s))
        s = v.to_s.strip
        s.empty? ? nil : s
      end

      private_class_method :string_present, :dig_string

      def self.exporter_entry(key)
        map = settings['exporters']
        return nil unless map.is_a?(Hash)

        entry = map[key.to_s]
        entry.is_a?(Hash) ? entry : nil
      end

      def self.lotteon_fallback_elasticsearch_url(exporter_key)
        return data_elasticsearch_url || elasticsearch_url if exporter_key.to_s == 'lotteon_products'

        elasticsearch_url
      end

      private_class_method :exporter_entry, :lotteon_fallback_elasticsearch_url

      def self.url_has_embedded_credentials?(url_string)
        uri = URI.parse(url_string.to_s)
        uri.user && !uri.user.empty?
      rescue URI::InvalidURIError
        false
      end
      private_class_method :url_has_embedded_credentials?

      # GCS bucket names and optional credentials from merged settings (+gcs+).
      class Gcs
        def initialize
          @config = load_config
        end

        def project_id
          @config['project_id']
        end

        def credentials
          cred = @config['credentials']
          s = cred.to_s.strip
          return s unless s.empty?

          p = Config.gcs_service_account_path.to_s.strip
          p.empty? ? nil : p
        end

        def bucket(name = :inventory)
          buckets = @config['buckets'] || {}
          value = buckets[name.to_s] || buckets[name.to_sym]

          value or raise "GCS bucket not found: #{name}"
        end

        private

        def load_config
          merged = EmTools::Core::Config.settings
          gcs = merged['gcs']
          unless use_settings_gcs?(gcs)
            raise 'GCS config missing: add gcs.buckets to your settings YAML ' \
                  '(see examples/config/settings.example.yml)'
          end

          normalize_gcs_settings(gcs)
        end

        def use_settings_gcs?(gcs)
          return false unless gcs.is_a?(Hash)

          buckets = gcs['buckets']
          buckets.is_a?(Hash) && !buckets.empty?
        end

        def normalize_gcs_settings(gcs)
          {
            'project_id' => gcs['project_id'],
            'credentials' => gcs['credentials'],
            'buckets' => stringify_buckets(gcs['buckets'])
          }
        end

        def stringify_buckets(buckets)
          return {} unless buckets.is_a?(Hash)

          buckets.each_with_object({}) do |(k, v), acc|
            acc[k.to_s] = v
          end
        end
      end
    end
  end
end
