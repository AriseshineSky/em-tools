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
    end
  end
end
