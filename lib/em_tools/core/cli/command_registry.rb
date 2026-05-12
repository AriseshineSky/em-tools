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
        class InvalidPluginCommandError < StandardError; end

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
          @plugin_namespaces = {}
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

        # Sections rendered by +HelpRenderer+, in display order:
        #   1. core sections (Elasticsearch & extracts, Inventory & object storage, ...)
        #   2. one section per plugin that contributes CLI commands, sorted by plugin name
        #
        # Each section is +[title, [Command, ...]]+. Empty sections are dropped by the renderer.
        def sections
          core_sections + plugin_sections
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
            @plugin_namespaces[plugin.name] = plugin.cli_namespace
            plugin.cli_commands.each do |name, klass|
              validate_plugin_command_name!(plugin, name)
              register(Command.new(name: name, klass: klass, section: nil, source: plugin.name))
            end
          end
        end

        def validate_plugin_command_name!(plugin, name)
          expected_prefix = "#{plugin.cli_namespace}:"
          return if name.to_s.start_with?(expected_prefix)

          raise InvalidPluginCommandError,
            "plugin #{plugin.name.inspect} CLI command #{name.inspect} must start with " \
              "#{expected_prefix.inspect} (override Plugin.cli_namespace if you want a different prefix)"
        end

        def register(command)
          @commands_by_name[command.name] = command
        end

        def core_sections
          @core_names_by_section.map do |section, names|
            [section, names.filter_map { |name| fetch(name) }]
          end
        end

        def plugin_sections
          plugin_commands_by_source
            .sort_by { |plugin_name, _| plugin_name.to_s }
            .map { |plugin_name, commands| [plugin_section_title(plugin_name), commands.sort_by(&:name)] }
        end

        def plugin_commands_by_source
          @commands_by_name.values
            .reject { |c| c.source == :core }
            .group_by(&:source)
        end

        def plugin_section_title(plugin_name)
          ns = @plugin_namespaces[plugin_name]
          ns ? "Plugin: #{plugin_name} (#{ns}:*)" : "Plugin: #{plugin_name}"
        end
      end
    end
  end
end
