# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module EmTools
  module Clients
    # Minimal HTTP client for Scrapyd JSON API (schedule / daemonstatus).
    class ScrapydClient
      class Error < StandardError; end

      def self.from_env(env = ENV)
        new(
          url: env["SCRAPYD_URL"],
          project: env["SCRAPYD_PROJECT"],
          username: env["SCRAPYD_USERNAME"],
          password: env["SCRAPYD_PASSWORD"],
        )
      end

      def initialize(url:, project:, username: nil, password: nil, open_timeout: 10, read_timeout: 30)
        @base_url = url.to_s.strip.chomp("/")
        @project = project.to_s.strip
        @username = username.to_s.strip
        @password = password.to_s
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def configured?
        !@base_url.empty? && !@project.empty?
      end

      def daemon_status
        get_json("daemonstatus.json")
      end

      def schedule_spider(spider:, settings: {})
        body = { project: @project, spider: spider.to_s }
        settings.each { |key, value| body[key.to_s] = value.to_s }
        post_form("schedule.json", body)
      end

      private

      def get_json(path)
        uri = build_uri(path)
        request = Net::HTTP::Get.new(uri)
        add_auth!(request)
        execute(uri, request)
      end

      def post_form(path, form)
        uri = build_uri(path)
        request = Net::HTTP::Post.new(uri)
        add_auth!(request)
        request.set_form_data(form)
        execute(uri, request)
      end

      def execute(uri, request)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.open_timeout = @open_timeout
          http.read_timeout = @read_timeout
          http.request(request)
        end
        raise Error, "HTTP #{response.code} for #{uri.path}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Error, "invalid JSON from #{uri.path}: #{e.message}"
      end

      def build_uri(path)
        URI.join("#{@base_url}/", path)
      end

      def add_auth!(request)
        return if @username.empty?

        request.basic_auth(@username, @password)
      end
    end
  end
end
