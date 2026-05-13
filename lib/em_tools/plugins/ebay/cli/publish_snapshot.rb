# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Ebay
      module Cli
        # +em-tools ebay listings publish-snapshot [marketplace]+ — publish an eBay
        # listings coverage snapshot for the given marketplace.
        class PublishSnapshot < Dry::CLI::Command
          desc "Publish an eBay listings coverage snapshot to Elasticsearch"

          argument :marketplace,
            desc: "Marketplace (e.g. us); defaults to EBAY_LISTINGS_COVERAGE_MARKETPLACE or 'us'"

          example [
            "                                  # default marketplace",
            "us                                # explicit marketplace",
          ]

          def call(marketplace: nil, **)
            EmTools::Core::Cli::Runner.run do
              EmTools::Core::PluginRegistry.fetch(:ebay).publish_snapshot(cli_marketplace: marketplace).run!
            end
          end
        end
      end
    end
  end
end
