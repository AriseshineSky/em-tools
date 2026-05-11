# frozen_string_literal: true

require "erb"
require "yaml"

module EmTools
  module Core
    module Inventory
      # Loads +sources+ (+gs://+ URIs) from merged settings (+inventory_sync+) or from an explicit YAML path.
      class SyncSources
        Source = Data.define(:gs_uri, :index, :refresh, :feed_id, :prune_obsolete)

        class Error < StandardError; end

        def self.load!(path = nil)
          p = path.to_s.strip
          return new(File.expand_path(p)).entries unless p.empty?

          settings = EmTools::Core::SettingsLoader.load
          node = inventory_sync_node_from_settings(settings)
          return new(nil, preloaded_node: node).entries if node

          raise Error,
            "No inventory sources: add a non-empty inventory_sync.sources list to your settings YAML, " \
              "or pass a dedicated YAML path: em-tools inventory-sync <path>"
        end

        def self.inventory_sync_node_from_settings(settings)
          return unless settings.is_a?(Hash)

          inv = settings["inventory_sync"]
          return unless inv.is_a?(Hash)

          sources = inv["sources"]
          return unless sources.is_a?(Array) && sources.any?

          inv
        end

        def initialize(path = nil, preloaded_node: nil)
          @path = path
          @preloaded_node = preloaded_node
        end

        def entries
          node = @preloaded_node || section(load_yaml!)
          list = validate_sources!(node)
          idx = default_index(node)
          ref = default_refresh(node)
          prune = default_prune_obsolete(node)
          list.each_with_index.map { |item, i| build_entry(item, i, idx, ref, prune) }
        end

        private

        def load_yaml!
          raise Error, "Inventory sync config path missing" if @path.nil? || @path.to_s.strip.empty?

          raw = File.read(@path)
          parsed = ERB.new(raw).result
          YAML.safe_load(parsed, permitted_classes: [], permitted_symbols: [], aliases: true)
        rescue Errno::ENOENT
          raise Error, "Inventory sync config not found: #{@path}"
        end

        def section(doc)
          env = ENV["APP_ENV"] || "development"
          doc.fetch(env) do
            raise Error, "Missing env #{env.inspect} in #{config_source_label} (define #{env} or default:)"
          end
        end

        def validate_sources!(node)
          list = node["sources"]
          if list.nil? || !list.is_a?(Array) || list.empty?
            env = ENV["APP_ENV"] || "development"
            raise Error, "sources must be a non-empty array in #{config_source_label} for env #{env.inspect}"
          end

          list
        end

        def config_source_label
          p = @path.to_s.strip
          p.empty? ? "merged settings (inventory_sync)" : p
        end

        def default_index(node)
          env_idx = ENV["INVENTORY_INDEX"].to_s.strip
          return env_idx unless env_idx.empty?

          node["index"] || Sync::INDEX
        end

        # rubocop:disable Naming/PredicateMethod -- "default_*" returns the default Boolean for a
        # field, it is not a predicate query against a subject; the verb-less name reads better.
        def default_refresh(node)
          truthy?(node["refresh"])
        end

        def default_prune_obsolete(node)
          truthy?(node["prune_obsolete"])
        end
        # rubocop:enable Naming/PredicateMethod

        def build_entry(item, idx, default_index, default_refresh, default_prune)
          case item
          when String
            string_source(item, idx, default_index, default_refresh, default_prune)
          when Hash
            hash_source(item, idx, default_index, default_refresh, default_prune)
          else
            raise Error, "sources[#{idx}] must be a String (gs://...) or a Hash, got #{item.class}"
          end
        end

        def string_source(item, idx, default_index, default_refresh, default_prune)
          uri = assert_gs_uri!(item.strip, idx)
          Source.new(
            gs_uri: uri,
            index: default_index,
            refresh: default_refresh,
            feed_id: nil,
            prune_obsolete: default_prune,
          )
        end

        def hash_source(item, idx, default_index, default_refresh, default_prune)
          uri = uri_from_item!(item, idx)
          Source.new(
            gs_uri: uri,
            index: coalesce_index(item["index"], default_index),
            refresh: coalesce_refresh(item, default_refresh),
            feed_id: coalesce_feed_id(item["feed_id"]),
            prune_obsolete: coalesce_prune_obsolete(item, default_prune),
          )
        end

        def uri_from_item!(item, idx)
          raw = item["uri"] || item["gs_uri"]
          raise Error, "sources[#{idx}] needs a uri or gs_uri key" if raw.nil? || raw.to_s.strip.empty?

          assert_gs_uri!(raw.to_s.strip, idx)
        end

        def coalesce_index(override, default_index)
          return default_index if override.nil? || override.to_s.strip.empty?

          override.to_s
        end

        def coalesce_refresh(item, default_refresh)
          return default_refresh unless item.key?("refresh")

          truthy?(item["refresh"])
        end

        # Explicit +feed_id+ in YAML only; otherwise nil so {EmTools::Core::Inventory::Sync} uses CSV +Source+
        # as +inventory_feed+.
        def coalesce_feed_id(override)
          return if override.nil?

          s = override.to_s.strip
          s.empty? ? nil : s
        end

        def coalesce_prune_obsolete(item, default_prune)
          return truthy?(item["prune_obsolete"]) if item.key?("prune_obsolete")

          default_prune
        end

        def assert_gs_uri!(uri, idx)
          return uri if uri.match?(%r{\Ags://[^/]+/.+\z}i)

          raise Error, "sources[#{idx}] invalid GCS URI (expected gs://bucket/path): #{uri.inspect}"
        end

        def truthy?(value)
          value == true || value.to_s.strip.downcase == "true" || value.to_s.strip == "1"
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
