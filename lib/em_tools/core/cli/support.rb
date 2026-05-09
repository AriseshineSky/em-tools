# frozen_string_literal: true

require 'json'
require 'yaml'

module EmTools
  module Core
    module Cli
      module Support
        module_function

        def require_elasticsearch_url!
          EmTools::Core::Config.elasticsearch_url
        rescue RuntimeError
          warn(
            'error: ELASTICSEARCH_URL is not set ' \
            '(.env or settings YAML; see examples/config/settings.example.yml)'
          )
          exit 1
        end

        def load_yaml_file!(path)
          p = File.expand_path(path)
          unless File.file?(p)
            warn "error: config file not found: #{p}"
            exit 1
          end
          YAML.safe_load(File.read(p), permitted_classes: [], permitted_symbols: [], aliases: true) || {}
        end

        def load_keywords(path)
          return [] unless path

          contents = File.read(path, encoding: 'utf-8')
          if path.end_with?('.json')
            Array(JSON.parse(contents))
          else
            contents.lines.map(&:strip).reject(&:empty?)
          end
        end
      end
    end
  end
end
