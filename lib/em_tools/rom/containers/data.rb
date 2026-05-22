# frozen_string_literal: true

module EmTools
  module Rom
    def self.data
      @data ||= ROM.container(:elasticsearch, url: ENV["DATA_ELASTICSEARCH_URL"]) do |config|
      end
    end
  end
end
