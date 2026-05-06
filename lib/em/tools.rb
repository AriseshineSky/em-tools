# frozen_string_literal: true

require 'zeitwerk'

module Em
  module Tools
  end
end

# `em-tools` loads `lib/em/tools.rb`; `Zeitwerk::Loader.for_gem` only supports a single segment
# under `lib/` (e.g. `lib/my_gem.rb`). Here the namespace lives under `lib/em/tools/`, so we push
# that directory onto the existing `Em::Tools` module.
loader = Zeitwerk::Loader.new
loader.tag = 'em-tools'
loader.inflector = Zeitwerk::GemInflector.new(__FILE__)
loader.push_dir("#{__dir__}/tools", namespace: Em::Tools)
loader.setup

Em::Tools::SettingsHydrator.apply_if_blank!

# `Em::Clients::ElasticsearchClient` lives under +lib/em/clients/+ (outside the Tools Zeitwerk root).
require_relative 'clients/elasticsearch_client'
require_relative 'tools/cli/app'
