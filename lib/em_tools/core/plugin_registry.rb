# frozen_string_literal: true

module EmTools
  module Core
    # Central catalogue of installed plugins. Each EmTools::Plugins::* class
    # declares its name and registers itself when its +plugin.rb+ is loaded:
    #
    #   def self.plugin_name = :ebay
    #   EmTools::Core::PluginRegistry.register(plugin_name, self)
    #
    # Lookups are by symbol; +fetch+ returns a fresh instance.
    #
    # As a defensive fallback +register+ also writes the symbol back to the
    # class via +Plugin::Base.plugin_name=+, so anonymous test classes that
    # don't declare +def self.plugin_name+ still get a name. For real plugin
    # classes that do declare it, the override wins (the writer's @ivar is
    # silently shadowed by the override) — that is intentional, the
    # plugin file is the single source of truth.
    module PluginRegistry
      class UnknownPluginError < StandardError; end

      @plugins = {}
      @mutex = Mutex.new

      def self.register(name, plugin_class)
        sym = name.to_sym
        plugin_class.plugin_name = sym if plugin_class.respond_to?(:plugin_name=)
        @mutex.synchronize { @plugins[sym] = plugin_class }
        plugin_class
      end

      def self.fetch(name)
        klass = @plugins[name.to_sym]
        raise UnknownPluginError, "unknown plugin: #{name.inspect} (registered: #{names.inspect})" unless klass

        klass.new
      end

      def self.fetch_class(name)
        klass = @plugins[name.to_sym]
        raise UnknownPluginError, "unknown plugin: #{name.inspect} (registered: #{names.inspect})" unless klass

        klass
      end

      def self.names
        @plugins.keys
      end

      def self.each_plugin
        return enum_for(:each_plugin) unless block_given?

        @plugins.each_value { |klass| yield klass.new }
      end

      # Test-only: clear the registry. Production code must not call this.
      def self.reset!
        @mutex.synchronize { @plugins.clear }
      end
    end
  end
end
