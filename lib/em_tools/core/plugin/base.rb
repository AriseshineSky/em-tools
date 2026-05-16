# frozen_string_literal: true

module EmTools
  module Core
    module Plugin
      # Contract every EmTools::Plugins::* class implements. Subclasses override the methods they
      # actually need (a plugin can be filter-only, source-only, sink-only, or expose ad-hoc
      # operations / CLI commands without participating in the engine model at all).
      #
      # The four Shopify-style capability slots are:
      #
      #   filters     -> array of classes responding to .new.call(record) returning truthy/falsy
      #   transforms  -> array of classes responding to .new.call(record) returning a record
      #   source      -> object responding to #each (yields records into the engine)
      #   sink        -> object responding to #index(record); optional #flush!
      #
      # Plugins also declare:
      #
      #   capabilities  -> nested hash of capability name => class or callable
      #   dependencies  -> shared runtime objects injected into capabilities / CLI
      #   cli_commands -> { 'subcommand path' => Dry::CLI::Command class } merged into the
      #                   +em-tools+ binary under the plugin's +cli_namespace+ subtree.
      # Raised when a plugin class is used (e.g. by +Cli::Registry+) before
      # it has been registered with {EmTools::Core::PluginRegistry.register}.
      # The canonical plugin file declares its own +plugin_name+ and then
      # registers itself in one step:
      #
      #   def self.plugin_name = :ebay
      #   EmTools::Core::PluginRegistry.register(plugin_name, self)
      #
      # Seeing this error means a +plugin.rb+ skipped that registration line
      # entirely (or shipped a stale +Plugin::Base+ subclass with neither a
      # +plugin_name+ override nor a registry call).
      class NotRegisteredError < StandardError; end

      class Base
        # The plugin identifier (a Symbol). Each concrete plugin **declares
        # its own name** with an endless method, and then passes it to the
        # registry — no derivation from the Ruby class name, no implicit
        # naming:
        #
        #   class Plugin < EmTools::Core::Plugin::Base
        #     def self.plugin_name = :ebay
        #
        #     EmTools::Core::PluginRegistry.register(plugin_name, self)
        #   end
        #
        # The +attr_reader+ below is the fallback when a subclass doesn't
        # override (e.g. tests that build anonymous plugin classes); the
        # +plugin_name=+ writer below lets +PluginRegistry.register+ poke
        # the value into those untyped classes. In the canonical case the
        # subclass override wins and the writer's @plugin_name ivar is
        # silently shadowed — that's intentional, the override is the
        # source of truth.
        class << self
          attr_reader :plugin_name
        end

        # Fallback writer used by +PluginRegistry.register+ for plugin
        # classes that don't declare +def self.plugin_name = :sym+. Real
        # plugins should always declare it (see the docstring above);
        # this exists so that tests and one-off anonymous plugin classes
        # can still get a name without boilerplate. Accepts +nil+ to clear,
        # which is how tests reset state on shared base classes.
        def self.plugin_name=(name)
          @plugin_name = name&.to_sym
        end

        # Subcommand subtree every CLI command in this plugin lives under.
        # Defaults to kebab-cased +plugin_name+ (so +:amazon_listings+
        # becomes +"amazon-listings"+). Override with a literal string when needed:
        #
        #   class Plugin < EmTools::Core::Plugin::Base
        #     def self.plugin_name   = :acme_feed
        #     def self.cli_namespace = "acme"
        #
        #     EmTools::Core::PluginRegistry.register(plugin_name, self)
        #   end
        #
        # Plugin command paths declared in +cli_commands+ are merged under
        # this prefix:
        #
        #   cli_namespace = "amazon"
        #   cli_commands  = { "products filter" => SomeCommand }
        #   # invoked as: em-tools amazon products filter
        def self.cli_namespace
          require_plugin_name!
          plugin_name.to_s.tr("_", "-")
        end

        # Asserts that a +plugin_name+ has been set. Called by the default
        # +cli_namespace+; subclasses that override +cli_namespace+ to a
        # literal string don't need this guard.
        def self.require_plugin_name!
          return unless plugin_name.nil?

          raise NotRegisteredError,
            "#{self} has no plugin_name set. " \
              "Declare it in the class body, e.g. " \
              "`def self.plugin_name = :your_name` and then " \
              "`EmTools::Core::PluginRegistry.register(plugin_name, self)`."
        end

        def name
          self.class.plugin_name
        end

        def cli_namespace
          self.class.cli_namespace
        end

        def filters
          []
        end

        def transforms
          []
        end

        def source(**_opts)
          nil
        end

        def sink(**_opts)
          nil
        end

        def capabilities
          {}
        end

        def dependencies
          {}
        end

        # Hash of <tt>"subcommand path"</tt> -> +Dry::CLI::Command+ class entries surfaced
        # by +em-tools+. Keys are space-separated subcommand paths *relative* to
        # +cli_namespace+; the registry prepends the namespace at boot.
        #
        #   cli_namespace = "amazon"
        #   cli_commands  = {
        #     "products filter"        => Cli::UploadableProductFilter,
        #     "products upload-from-es" => Cli::AmzUploadProductsFromEs,
        #     "coverage publish-snapshot" => Cli::PublishSnapshot,
        #   }
        #
        #   # -> em-tools amazon products filter
        #   # -> em-tools amazon products upload-from-es
        #   # -> em-tools amazon coverage publish-snapshot
        def cli_commands
          {}
        end
      end
    end
  end
end
