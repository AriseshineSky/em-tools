# frozen_string_literal: true

require "rom"
require "rom-elasticsearch"

module EmTools
  module Rom
    def self.es_primary
      @es_primary ||= ROM.container(:elasticsearch, url: ENV["ELASTICSEARCH_URL"]) do |config|
      end
    end

    def self.es_data
      @es_data ||= ROM.container(:elasticsearch, url: ENV["DATA_ELASTICSEARCH_URL"]) do |config|
      end
    end
  end
end
