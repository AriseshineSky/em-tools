# frozen_string_literal: true

module EmTools
  module Core
    # Central catalogue of installed plugins. Each EmTools::Plugins::* class registers itself when its
    # +plugin.rb+ is loaded via +EmTools::Core::PluginRegistry.register(:name, self)+. Lookups are by
    # symbol; +fetch+ returns a fresh instance.
    module PluginRegistry
      class UnknownPluginError < StandardError; end

      @plugins = {}
      @mutex = Mutex.new

      class << self
        def register(name, plugin_class)
          @mutex.synchronize { @plugins[name.to_sym] = plugin_class }
          plugin_class
        end

        def fetch(name)
          klass = @plugins[name.to_sym]
          raise UnknownPluginError, "unknown plugin: #{name.inspect} (registered: #{names.inspect})" unless klass

          klass.new
        end

        def fetch_class(name)
          klass = @plugins[name.to_sym]
          raise UnknownPluginError, "unknown plugin: #{name.inspect} (registered: #{names.inspect})" unless klass

          klass
        end

        def names
          @plugins.keys
        end

        def each_plugin
          return enum_for(:each_plugin) unless block_given?

          @plugins.each_value { |klass| yield klass.new }
        end

        # Test-only: clear the registry. Production code must not call this.
        def reset!
          @mutex.synchronize { @plugins.clear }
        end
      end
    end
  end
end
