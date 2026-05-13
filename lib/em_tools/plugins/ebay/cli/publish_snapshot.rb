# frozen_string_literal: true

module EmTools
  module Plugins
    module Ebay
      module Cli
        class PublishSnapshot < EmTools::Core::Plugin::Cli::Base
          def banner
            <<~BANNER
              Usage: em-tools ebay:listings:publish-snapshot [marketplace]

              Publish an eBay listings coverage snapshot.
              Optional marketplace argument (e.g. us); otherwise EBAY_LISTINGS_COVERAGE_MARKETPLACE or default us.
            BANNER
          end

          def execute!(_options, argv)
            mp = argv.shift
            unless argv.empty?
              warn("error: unexpected arguments: #{argv.join(" ")}")
              exit(1)
            end

            EmTools::Core::Cli::Runner.run do
              EmTools::Core::PluginRegistry.fetch(:ebay).publish_snapshot(cli_marketplace: mp).run!
            end
          end
        end
      end
    end
  end
end
