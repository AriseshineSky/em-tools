# frozen_string_literal: true

module Em
  module Tools
    class Config
      def self.elasticsearch_url
        ENV.fetch('ELASTICSEARCH_URL') do
          raise 'ELASTICSEARCH_URL missing'
        end
      end

      def self.blacklist_api_endpoint
        ENV['BLACKLIST_API_ENDPOINT']
      end

      def self.blacklist_api_path
        ENV['BLACKLIST_API_PATH']
      end

      def self.blacklist_api_key
        ENV['BLACKLIST_API_KEY']
      end

      def self.blacklist_api_token
        ENV['BLACKLIST_API_TOKEN'] || blacklist_api_key
      end

      # Path to a GCS service account JSON key (optional; used by gcs rake tasks / GcsHelper).
      def self.gcs_service_account_path
        File.expand_path(ENV['GCS_SERVICE_ACCOUNT_PATH'])
      end

      # ========================
      # 新增：GCS 配置入口 ⭐
      # ========================
      def self.gcs
        @gcs ||= Gcs.new
      end

      # ========================
      # 内部类：GCS Config
      # ========================
      class Gcs
        def initialize
          @config = load_config
        end

        def project_id
          @config['project_id']
        end

        def credentials
          @config['credentials'] ||
            Config.gcs_service_account_path
        end

        def bucket(name = :inventory)
          buckets = @config['buckets'] || {}
          value = buckets[name.to_s] || buckets[name.to_sym]

          value or raise "GCS bucket not found: #{name}"
        end

        private

        def load_config
          env = ENV['APP_ENV'] || 'development'

          path = File.expand_path('../../../config/gcs.yml', __dir__)
          raw = File.read(path)
          parsed = ERB.new(raw).result

          yaml = YAML.safe_load(parsed, aliases: true)

          yaml.fetch(env) do
            raise "Missing env #{env} in gcs.yml"
          end
        end
      end
    end
  end
end
