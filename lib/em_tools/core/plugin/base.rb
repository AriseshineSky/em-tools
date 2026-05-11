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
      #   cli_commands -> { 'cli-name' => CommandClass } merged into the +em-tools+ binary
      class Base
        # Default plugin identifier: lowercased, snake_cased class name within EmTools::Plugins.
        # e.g. EmTools::Plugins::AmazonUploadable -> :amazon_uploadable
        def self.plugin_name
          short = name.to_s.split("::").last
          underscored = short.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
          underscored.to_sym
        end

        def name
          self.class.plugin_name
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

        def cli_commands
          {}
        end
      end
    end
  end
end
