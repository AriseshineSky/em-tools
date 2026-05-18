# frozen_string_literal: true

require "erb"
require "yaml"

module EmTools
  module Core
    module Inventory
      # Loads +sources+ (+gs://+ URIs) from merged settings (+inventory_sync+, +google_ads_catalog_sync+, …)
      # or from an explicit YAML path.
      class SyncSources
        # Default +AMZ_{marketplace}-Inv.csv+ market codes when YAML uses +marketplaces: all+.
        DEFAULT_AMAZON_INVENTORY_MARKETPLACES = %w[AE CA US DE UK IN IT MX JP TR].freeze

        # +cluster+ is the **name** of the ES cluster to write into ("primary",
        # "data"/"analytics", or any custom +elasticsearch_clusters+ key).
        # +nil+ means "use whatever default the orchestrator picks" — usually
        # +primary+, or +data+ when the operator passed +--data+.
        #
        # +drop_fields+ lists per-doc fields to strip before bulk-indexing
        # (snake_cased like the headers stored on the doc). Empty / nil means no transform.
        Source = Data.define(
          :gs_uri, :index, :refresh, :feed_id, :prune_obsolete, :cluster, :drop_fields, :format
        )

        class Error < StandardError; end

        def self.load!(path = nil, profile: SyncProfile::INVENTORY)
          p = path.to_s.strip
          return new(File.expand_path(p), profile: profile).entries unless p.empty?

          settings = EmTools::Core::SettingsLoader.load
          node = node_from_settings(settings, profile.settings_key)
          return new(nil, preloaded_node: node, profile: profile).entries if node

          raise Error,
            "No #{profile.config_label} sources: add a non-empty #{profile.settings_key}.sources list " \
              "to your settings YAML, or pass a dedicated YAML path"
        end

        def self.node_from_settings(settings, settings_key)
          return unless settings.is_a?(Hash)

          inv = settings[settings_key]
          return unless inv.is_a?(Hash)

          sources = inv["sources"]
          return unless sources.is_a?(Array) && sources.any?

          inv
        end

        def initialize(path = nil, preloaded_node: nil, profile: SyncProfile::INVENTORY)
          @path = path
          @preloaded_node = preloaded_node
          @profile = profile
        end

        def entries
          node = @preloaded_node || section(load_yaml!)
          list = expand_sources!(validate_sources!(node))
          defaults = {
            index: default_index(node),
            refresh: default_refresh(node),
            prune_obsolete: default_prune_obsolete(node),
            cluster: default_cluster(node),
            drop_fields: default_drop_fields(node),
          }
          list.each_with_index.map { |item, i| build_entry(item, i, defaults) }
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
          p.empty? ? "merged settings (#{@profile.config_label})" : p
        end

        def default_index(node)
          env_idx = ENV[@profile.env_key("INDEX")].to_s.strip
          return env_idx unless env_idx.empty?

          node["index"] || @profile.default_index
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

        def default_cluster(node)
          v = node["cluster"].to_s.strip
          v.empty? ? nil : v
        end

        def default_drop_fields(node)
          parse_drop_fields(node["drop_fields"])
        end

        # Accepts +Array<String>+, comma-separated +String+, or +nil+. Returns an
        # array of normalized field names (no surprises like +nil+ entries).
        def parse_drop_fields(value)
          case value
          when nil then []
          when Array then value.map { |v| v.to_s.strip }.reject(&:empty?)
          when String then value.split(",").map(&:strip).reject(&:empty?)
          else
            raise Error, "drop_fields must be an array or comma-separated string, got #{value.class}"
          end
        end

        def expand_sources!(list)
          list.flat_map.with_index { |item, idx| expand_source_item(item, idx) }
        end

        # Expands +gs_uri_template: gs://bucket/AMZ_{marketplace}-Inv.csv+ with +marketplaces:+ list.
        def expand_source_item(item, idx)
          case item
          when String
            [item]
          when Hash
            template = template_uri_from_hash(item)
            markets = item["marketplaces"]
            return [item] unless template && markets

            codes = resolve_marketplace_codes(markets, idx)
            base = item.dup
            %w[gs_uri_template template uri_template marketplaces].each { |k| base.delete(k) }

            codes.map do |code|
              uri = template.gsub("{marketplace}", code)
              assert_gs_uri!(uri, idx)
              base.merge("uri" => uri)
            end
          else
            raise Error, "sources[#{idx}] must be a String (gs://...) or a Hash, got #{item.class}"
          end
        end

        def template_uri_from_hash(item)
          raw = item["gs_uri_template"] || item["template"] || item["uri_template"]
          s = raw.to_s.strip
          s.empty? ? nil : s
        end

        def resolve_marketplace_codes(markets, idx)
          case markets
          when Array
            list = markets.map { |m| m.to_s.strip }.reject(&:empty?)
            if list.size == 1 && list.first.casecmp("all").zero?
              DEFAULT_AMAZON_INVENTORY_MARKETPLACES.dup
            else
              list.map(&:upcase)
            end
          when String
            s = markets.strip
            return DEFAULT_AMAZON_INVENTORY_MARKETPLACES.dup if s.casecmp("all").zero?

            s.split(",").map(&:strip).reject(&:empty?).map(&:upcase)
          else
            raise Error, "sources[#{idx}] marketplaces must be an array or comma-separated string"
          end
        end

        def build_entry(item, idx, defaults)
          case item
          when String
            string_source(item, idx, defaults)
          when Hash
            hash_source(item, idx, defaults)
          else
            raise Error, "sources[#{idx}] must be a String (gs://...) or a Hash, got #{item.class}"
          end
        end

        def string_source(item, idx, defaults)
          uri = assert_gs_uri!(item.strip, idx)
          Source.new(
            gs_uri: uri,
            index: defaults[:index],
            refresh: defaults[:refresh],
            feed_id: nil,
            prune_obsolete: defaults[:prune_obsolete],
            cluster: defaults[:cluster],
            drop_fields: defaults[:drop_fields],
            format: infer_format(uri, nil),
          )
        end

        def hash_source(item, idx, defaults)
          uri = uri_from_item!(item, idx)
          Source.new(
            gs_uri: uri,
            index: coalesce_index(item["index"], defaults[:index]),
            refresh: coalesce_refresh(item, defaults[:refresh]),
            feed_id: coalesce_feed_id(item["feed_id"] || item["source"]),
            prune_obsolete: coalesce_prune_obsolete(item, defaults[:prune_obsolete]),
            cluster: coalesce_cluster(item, defaults[:cluster]),
            drop_fields: coalesce_drop_fields(item, defaults[:drop_fields]),
            format: infer_format(uri, item["format"]),
          )
        end

        def infer_format(uri, explicit)
          return parse_format!(explicit) unless explicit.nil?

          uri.to_s.match?(/\.txt\z/i) ? :asin_list : :csv
        end

        def parse_format!(raw)
          case raw.to_s.strip.downcase
          when "asin_list", "asins", "seed" then :asin_list
          when "tab_json", "tab-json", "google_ads_feed", "tsv_json" then :tab_json
          when "txt" then :asin_list
          when "csv", "inventory" then :csv
          else
            raise Error, "unknown source format #{raw.inspect} (use csv, asin_list, or tab_json)"
          end
        end

        def coalesce_drop_fields(item, default_drop_fields)
          return default_drop_fields unless item.key?("drop_fields")

          parse_drop_fields(item["drop_fields"])
        end

        def coalesce_cluster(item, default_cluster)
          return default_cluster unless item.key?("cluster")

          v = item["cluster"].to_s.strip
          v.empty? ? default_cluster : v
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
