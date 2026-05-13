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
      class Base
        # Default plugin identifier: snake_cased namespace under EmTools::Plugins.
        #
        #   EmTools::Plugins::AmazonUploadable::Plugin -> :amazon_uploadable
        #   EmTools::Plugins::Storefront::Plugin       -> :storefront
        def self.plugin_name
          parts = name.to_s.split("::")
          short = parts.last == "Plugin" && parts.length >= 2 ? parts[-2] : parts.last
          underscored = short.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
          underscored.to_sym
        end

        # Subcommand subtree every CLI command in this plugin lives under. Default is
        # the kebab-case +plugin_name+; override for a shorter, friendlier prefix:
        #
        #   def self.cli_namespace = "amz-uploadable"
        #
        # Plugin command paths (declared in +cli_commands+) are merged under this prefix:
        #
        #   cli_namespace = "amz-uploadable"
        #   cli_commands   = { "filter" => SomeCommand }
        #   # invoked as: em-tools amz-uploadable filter
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

        # Hash of <tt>"subcommand path"</tt> -> +Dry::CLI::Command+ class entries surfaced
        # by +em-tools+. Keys are space-separated subcommand paths *relative* to
        # +cli_namespace+; the registry prepends the namespace at boot.
        #
        #   cli_namespace = "amz-uploadable"
        #   cli_commands  = {
        #     "filter"          => Cli::UploadableProductFilter,
        #     "upload-from-es"  => Cli::AmzUploadProductsFromEs,
        #     # multi-level paths are allowed:
        #     "products filter" => Cli::SomeNestedCommand,
        #   }
        #
        #   # -> em-tools amz-uploadable filter
        #   # -> em-tools amz-uploadable upload-from-es
        #   # -> em-tools amz-uploadable products filter
        def cli_commands
          {}
        end
      end
    end
  end
end
