# frozen_string_literal: true

module EmTools
  module Rom
    def self.primary
      @primary ||= ROM.container(:elasticsearch, url: ENV["ELASTICSEARCH_URL"]) do |config|
      end
    end
  end
end
