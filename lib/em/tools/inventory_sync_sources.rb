# frozen_string_literal: true

require 'erb'
require 'yaml'

module Em
  module Tools
    # Loads +sources+ (a list of +gs://+ URIs) from +config/inventory_sync.yml+ (or a given path).
    class InventorySyncSources
      Source = Data.define(:gs_uri, :index, :refresh)

      class Error < StandardError; end

      class << self
        def load!(path = nil)
          new(path).entries
        end

        def default_config_path
          File.expand_path('../../../config/inventory_sync.yml', __dir__)
        end
      end

      def initialize(path = nil)
        @path = path || self.class.default_config_path
      end

      def entries
        node = section(load_yaml!)
        list = validate_sources!(node)
        idx = default_index(node)
        ref = default_refresh(node)
        list.each_with_index.map { |item, i| build_entry(item, i, idx, ref) }
      end

      private

      def load_yaml!
        raw = File.read(@path)
        parsed = ERB.new(raw).result
        YAML.safe_load(parsed, permitted_classes: [], permitted_symbols: [], aliases: true)
      rescue Errno::ENOENT
        raise Error, "Inventory sync config not found: #{@path}"
      end

      def section(doc)
        env = ENV['APP_ENV'] || 'development'
        doc.fetch(env) do
          raise Error, "Missing env #{env.inspect} in #{@path} (define #{env} or default:)"
        end
      end

      def validate_sources!(node)
        list = node['sources']
        if list.nil? || !list.is_a?(Array) || list.empty?
          env = ENV['APP_ENV'] || 'development'
          raise Error, "sources must be a non-empty array in #{@path} for env #{env.inspect}"
        end

        list
      end

      def default_index(node)
        node['index'] || InventorySync::INDEX
      end

      def default_refresh(node)
        truthy?(node['refresh'])
      end

      def build_entry(item, idx, default_index, default_refresh)
        case item
        when String
          string_source(item, idx, default_index, default_refresh)
        when Hash
          hash_source(item, idx, default_index, default_refresh)
        else
          raise Error, "sources[#{idx}] must be a String (gs://...) or a Hash, got #{item.class}"
        end
      end

      def string_source(item, idx, default_index, default_refresh)
        Source.new(
          gs_uri: assert_gs_uri!(item.strip, idx),
          index: default_index,
          refresh: default_refresh
        )
      end

      def hash_source(item, idx, default_index, default_refresh)
        uri = item['uri'] || item['gs_uri']
        raise Error, "sources[#{idx}] needs a uri or gs_uri key" if uri.nil? || uri.to_s.strip.empty?

        Source.new(
          gs_uri: assert_gs_uri!(uri.to_s.strip, idx),
          index: coalesce_index(item['index'], default_index),
          refresh: coalesce_refresh(item, default_refresh)
        )
      end

      def coalesce_index(override, default_index)
        return default_index if override.nil? || override.to_s.strip.empty?

        override.to_s
      end

      def coalesce_refresh(item, default_refresh)
        return default_refresh unless item.key?('refresh')

        truthy?(item['refresh'])
      end

      def assert_gs_uri!(uri, idx)
        return uri if uri.match?(%r{\Ags://[^/]+/.+\z}i)

        raise Error, "sources[#{idx}] invalid GCS URI (expected gs://bucket/path): #{uri.inspect}"
      end

      def truthy?(value)
        value == true || value.to_s.strip.downcase == 'true' || value.to_s.strip == '1'
      end
    end
  end
end
