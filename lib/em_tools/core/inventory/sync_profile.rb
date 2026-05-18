# frozen_string_literal: true

module EmTools
  module Core
    module Inventory
      # Configuration bundle for GCS CSV → Elasticsearch catalog/inventory sync.
      # Keeps env keys, settings YAML section, default index, and ES feed field name
      # aligned per use case ({SyncProfile::INVENTORY} vs plugin-specific profiles).
      class SyncProfile
        attr_reader :settings_key, :env_prefix, :default_index, :default_gs_uri, :feed_field, :config_label

        def initialize(settings_key:, env_prefix:, default_index:, default_gs_uri:, feed_field:, config_label:)
          @settings_key = settings_key.to_s
          @env_prefix = env_prefix.to_s
          @default_index = default_index.to_s
          @default_gs_uri = default_gs_uri.to_s
          @feed_field = feed_field.to_s
          @config_label = config_label.to_s
        end

        # @param suffix [String] e.g. +"INDEX"+ → +"INVENTORY_INDEX"+
        def env_key(suffix)
          "#{env_prefix}#{suffix}"
        end
      end

      SyncProfile::INVENTORY = SyncProfile.new(
        settings_key: "inventory_sync",
        env_prefix: "INVENTORY_",
        default_index: Sync::INDEX,
        default_gs_uri: "gs://em-bucket/boyner-Inv.csv",
        feed_field: "inventory_feed",
        config_label: "inventory_sync",
      )
    end
  end
end
