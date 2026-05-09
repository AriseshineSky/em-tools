# frozen_string_literal: true

require 'net/http'
require 'json'

module EmTools
  module Core
    module Blacklist
      class Loader
        def fetch
          uri = build_uri
          res = Net::HTTP.get_response(uri)

          raise "Blacklist API failed: #{res.code}" unless res.is_a?(Net::HTTPSuccess)

          JSON.parse(res.body)
        end

        def fetch_keywords
          data = fetch

          Array(data['blacklist_keywords']).flat_map do |item|
            parse_keywords(item['keywords'])
          end.uniq
        end

        def initialize; end

        private

        def build_uri
          uri = URI.join(
            EmTools::Core::Config.blacklist_api_endpoint,
            EmTools::Core::Config.blacklist_api_path.to_s
          )

          uri.query = URI.encode_www_form(
            token: EmTools::Core::Config.blacklist_api_token
          )

          uri
        end

        def parse_keywords(keywords)
          case keywords
          when String
            [keywords]
          when Array
            keywords
          else
            []
          end
        end
      end
    end
  end
end
