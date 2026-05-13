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
      #   cli_commands -> { 'cli-name' => CommandClass } merged into the +em-tools+ binary
      class Base
        # Default plugin identifier: snake_cased namespace under EmTools::Plugins.
        #
        #   EmTools::Plugins::AmazonUploadable::Plugin -> :amazon_uploadable
        #   EmTools::Plugins::Storefront::Plugin       -> :storefront
        #
        # When the final class is literally +Plugin+ (the convention this project uses), we
        # take the parent module's short name; otherwise we fall back to the class itself.
        def self.plugin_name
          parts = name.to_s.split("::")
          short = parts.last == "Plugin" && parts.length >= 2 ? parts[-2] : parts.last
          underscored = short.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
          underscored.to_sym
        end

        # Namespace prefix every CLI command in this plugin must use.
        # Default: kebab-case of +plugin_name+ (e.g. +:amazon_uploadable+ -> +"amazon-uploadable"+).
        # Override to choose a shorter / more memorable prefix:
        #
        #   def self.cli_namespace = "amz"
        def self.cli_namespace
          plugin_name.to_s.tr("_", "-")
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

        # Hash of <tt>"namespace:command"</tt> -> CommandClass entries surfaced by +em-tools+.
        # Names MUST start with +"#{cli_namespace}:"+; +CommandRegistry+ enforces this at boot.
        def cli_commands
          {}
        end
      end
    end
  end
end
