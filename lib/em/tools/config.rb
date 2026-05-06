# frozen_string_literal: true

module Em
  module Tools
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

        raise 'ELASTICSEARCH_URL missing (set in .env or settings YAML elasticsearch.url; see examples/config/settings.example.yml)'
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

      # Path to a GCS service account JSON key (optional; used by gcs rake tasks / GcsHelper).
      def self.gcs_service_account_path
        File.expand_path(ENV['GCS_SERVICE_ACCOUNT_PATH'].to_s)
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

      # ========================
      # 新增：GCS 配置入口 ⭐
      # ========================
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
          merged = Em::Tools::Config.settings
          gcs = merged['gcs']
          return normalize_gcs_settings(gcs) if use_settings_gcs?(gcs)

          legacy_gcs_yaml_config
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

        def legacy_gcs_yaml_config
          path = File.expand_path('../../../config/gcs.yml', __dir__)
          return {} unless File.file?(path)

          env = ENV['APP_ENV'] || 'development'
          raw = File.read(path)
          parsed = ERB.new(raw).result
          yaml = YAML.safe_load(parsed, aliases: true)
          yaml = {} unless yaml.is_a?(Hash)
          yaml.fetch(env) do
            raise "Missing env #{env} in config/gcs.yml (legacy; use settings YAML gcs: section instead)"
          end
        end
      end
    end
  end
end
