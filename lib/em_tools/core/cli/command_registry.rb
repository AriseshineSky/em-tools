# frozen_string_literal: true

module EmTools
  module Core
    module Cli
      # Immutable-ish catalogue of available CLI commands.
      #
      # The registry is built once after plugins have registered. Runtime
      # dispatch then becomes a hash lookup, not "merge core + scan plugins"
      # on every help render or command invocation.
      class CommandRegistry
        Command = Data.define(:name, :klass, :section, :source) do
          def plugin?
            source != :core
          end
        end

        CORE_SECTIONS = [
          ["Elasticsearch & extracts", [
            [CommandNames::DUMP, Commands::Dump],
            [CommandNames::ES_DUMP_INDEX, Commands::EsDumpIndex],
            [CommandNames::ES_DOWNLOAD_PRODUCT, Commands::EsDownloadProduct],
          ],],
          ["Inventory & object storage", [
            [CommandNames::INVENTORY_SYNC, Commands::InventorySync],
            [CommandNames::INVENTORY_SYNC_FROM_GCS, Commands::InventorySyncFromGcs],
            [CommandNames::GCS_DOWNLOAD_SEEDS, Commands::GcsDownloadSeeds],
          ],],
          ["Marketplace monitoring snapshots", [
            [CommandNames::LOWEST_OFFER_PUBLISH_SNAPSHOT, Commands::LowestOfferPublishSnapshot],
            [CommandNames::LOWEST_OFFER_DOWNLOAD_AND_PUBLISH, Commands::LowestOfferDownloadAndPublish],
            [CommandNames::EBAY_LISTINGS_PUBLISH_SNAPSHOT, Commands::EbayListingsPublishSnapshot],
          ],],
          ["Reference data", [
            [CommandNames::BLACKLIST_DOWNLOAD, Commands::BlacklistDownload],
          ],],
        ].freeze

        @default_mutex = Mutex.new

        def self.default
          @default_mutex.synchronize do
            @default ||= new.freeze
          end
        end

        # Test-only: force the next call to +.default+ to re-scan plugins.
        def self.reset_default!
          @default_mutex.synchronize { @default = nil }
        end

        def initialize(plugin_registry: EmTools::Core::PluginRegistry)
          @plugin_registry = plugin_registry
          @commands_by_name = {}
          @core_names_by_section = {}
          register_core_commands
          register_plugin_commands
        end

        def fetch(raw_name)
          @commands_by_name[canonical_name(raw_name)]
        end

        def command_table
          @commands_by_name.transform_values(&:klass)
        end

        def names
          @commands_by_name.keys
        end

        def sections
          sections = core_sections
          plugin_commands = unsectioned_plugin_commands(sections)
          sections << ["Plugins & other", plugin_commands] if plugin_commands.any?
          sections
        end

        private

        def canonical_name(raw_name)
          CommandNames::ALIASES.fetch(raw_name.to_s, raw_name.to_s)
        end

        def register_core_commands
          CORE_SECTIONS.each do |section, commands|
            @core_names_by_section[section] = commands.map(&:first)
            commands.each do |name, klass|
              register(Command.new(name: name, klass: klass, section: section, source: :core))
            end
          end
        end

        def register_plugin_commands
          @plugin_registry.each_plugin do |plugin|
            plugin.cli_commands.each do |name, klass|
              register(Command.new(name: name, klass: klass, section: nil, source: plugin.name))
            end
          end
        end

        def register(command)
          @commands_by_name[command.name] = command
        end

        def core_sections
          @core_names_by_section.map do |section, names|
            [section, names.filter_map { |name| fetch(name) }]
          end
        end

        def unsectioned_plugin_commands(core_sections)
          sectioned_names = core_sections.flat_map { |_section, commands| commands.map(&:name) }
          names.reject { |name| sectioned_names.include?(name) }
            .sort
            .filter_map { |name| fetch(name) }
        end
      end
    end
  end
end
