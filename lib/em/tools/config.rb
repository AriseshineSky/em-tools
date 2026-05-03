# frozen_string_literal: true

module Em
  module Tools
    class Config
      def self.elasticsearch_url
        ENV.fetch("ELASTICSEARCH_URL") do
          raise "ELASTICSEARCH_URL missing"
        end
      end

      def self.blacklist_api_endpoint
        ENV["BLACKLIST_API_ENDPOINT"]
      end

      def self.blacklist_api_path
        ENV["BLACKLIST_API_PATH"]
      end

      def self.blacklist_api_key
        ENV["BLACKLIST_API_KEY"]
      end

      def self.blacklist_api_token
        ENV["BLACKLIST_API_TOKEN"] || blacklist_api_key
      end
    end
  end
end
