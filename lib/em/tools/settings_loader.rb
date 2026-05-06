# frozen_string_literal: true

require 'erb'
require 'yaml'

module Em
  module Tools
    # Loads merged app YAML with ERB: +EM_TOOLS_SETTINGS_PATH+ if set, else +config/settings.yml+ when
    # present, else committed +examples/config/settings.example.yml+. Merges +default+ with +APP_ENV+
    # (+RAILS_ENV+ / +RACK_ENV+ fallback).
    module SettingsLoader
      module_function

      def gem_root
        File.expand_path('../../..', __dir__)
      end

      def default_path
        explicit = ENV['EM_TOOLS_SETTINGS_PATH'].to_s.strip
        return File.expand_path(explicit) unless explicit.empty?

        local = File.join(gem_root, 'config', 'settings.yml')
        return local if File.file?(local)

        File.join(gem_root, 'examples', 'config', 'settings.example.yml')
      end

      # @return [Hash{String=>Object}] string keys only; empty hash if file missing or unreadable
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def load(path = nil)
        path = path.nil? ? default_path : File.expand_path(path.to_s)
        return {} unless File.file?(path)

        raw = File.read(path)
        parsed = ERB.new(raw).result

        tree = YAML.safe_load(parsed, permitted_classes: [], permitted_symbols: [], aliases: true)
        tree = {} unless tree.is_a?(Hash)

        env = (ENV['APP_ENV'] || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development').to_s
        base = tree['default'].is_a?(Hash) ? stringify_keys(tree['default']) : {}
        overlay = tree[env].is_a?(Hash) ? stringify_keys(tree[env]) : {}
        deep_merge(base, overlay)
      rescue ArgumentError, Psych::SyntaxError, SystemCallError => e
        warn "em-tools: settings YAML error (#{path}): #{e.message}"
        {}
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      def deep_merge(left, right)
        left.merge(right) do |_k, v1, v2|
          if v1.is_a?(Hash) && v2.is_a?(Hash)
            deep_merge(v1, v2)
          else
            v2
          end
        end
      end

      def stringify_keys(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys(v) }
        when Array
          obj.map { |e| stringify_keys(e) }
        else
          obj
        end
      end

      # Env names for per-site overrides, e.g. +EM_TOOLS_SITE_ACME_TOKEN+ for sites.acme.token in YAML.
      def site_env_prefix(name)
        "EM_TOOLS_SITE_#{name.to_s.upcase.tr('-', '_')}_"
      end
    end
  end
end
