# frozen_string_literal: true

require_relative "tools/version"
require "zeitwerk"

module Em
  module Tools
    class Error < StandardError; end

  end
end
loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("html_parser" => "HTMLParser")
loader.setup
# Flat `elasticsearch_client.rb` would otherwise be resolved as Elasticsearch::Client under `elasticsearch.rb`.
require_relative "tools/elasticsearch_client"
