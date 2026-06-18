# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module EmTools
  module Core
    module Monitoring
      # Posts run events to the monitoring-dashboard Rails API.
      class Client
        def self.from_env(env = ENV)
          new(
            base_url: env["MONITOR_BASE_URL"],
            api_token: env["MONITOR_API_TOKEN"],
          )
        end

        def initialize(base_url:, api_token:, http: nil)
          @base_url = base_url.to_s.strip.chomp("/")
          @api_token = api_token.to_s.strip
          @http = http
        end

        def configured?
          !@base_url.empty? && !@api_token.empty?
        end

        def post_inventory_sync_run(payload)
          post("/api/v1/inventory_sync_runs", payload)
        end

        def post(path, payload, retries: 2)
          return unless configured?

          uri = URI.parse("#{@base_url}#{path}")
          body = JSON.generate(payload)
          headers = {
            "Authorization" => "Bearer #{@api_token}",
            "Content-Type" => "application/json",
          }

          (0..retries).each do |attempt|
            begin
              response = request(uri, body, headers)
              return response if response.is_a?(Net::HTTPSuccess)

              return response if attempt == retries
            rescue StandardError
              return nil if attempt == retries
            end
            sleep(0.5 * (2**attempt))
          end
          nil
        end

        private

        def request(uri, body, headers)
          if @http
            return @http.request(build_request(uri, body, headers))
          end

          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
            http.open_timeout = 10
            http.read_timeout = 10
            http.request(build_request(uri, body, headers))
          end
        end

        def build_request(uri, body, headers)
          req = Net::HTTP::Post.new(uri.request_uri)
          headers.each { |key, value| req[key] = value }
          req.body = body
          req
        end
      end
    end
  end
end
