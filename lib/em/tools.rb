# frozen_string_literal: true

require "zeitwerk"

module Em
  module Tools
  end
end

# `em-tools` loads `lib/em/tools.rb`; `Zeitwerk::Loader.for_gem` only supports a single segment
# under `lib/` (e.g. `lib/my_gem.rb`). Here the namespace lives under `lib/em/tools/`, so we push
# that directory onto the existing `Em::Tools` module.
loader = Zeitwerk::Loader.new
loader.tag = "em-tools"
loader.inflector = Zeitwerk::GemInflector.new(__FILE__)
loader.push_dir("#{__dir__}/tools", namespace: Em::Tools)
loader.setup

# `elasticsearch.rb` defines `Em::Tools::Elasticsearch`, so Zeitwerk would expect
# `elasticsearch/client.rb` for `ElasticsearchClient` instead of `elasticsearch_client.rb`.
require_relative "tools/elasticsearch_client"
