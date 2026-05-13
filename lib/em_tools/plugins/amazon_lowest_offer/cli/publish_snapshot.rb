# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonLowestOffer
      module Cli
        class PublishSnapshot < EmTools::Core::Plugin::Cli::Base
          def banner
            <<~BANNER
              Usage: em-tools amazon-lowest-offer:coverage:publish-snapshot [marketplace ...]

              Publish the lowest-offer coverage snapshot to Elasticsearch.
              Optional marketplace codes: us ca jp or us,ca; otherwise LOWEST_OFFER_MARKETPLACES or default nine markets.
            BANNER
          end

          def execute!(_options, argv)
            cli_mps = argv.flat_map { |a| a.split(",") }.map(&:strip).reject(&:empty?).map(&:downcase).join(",")
            cli_mps = nil if cli_mps.empty?

            EmTools::Core::Cli::Runner.run do
              EmTools::Core::PluginRegistry.fetch(:amazon_lowest_offer).publish_snapshot(
                cli_marketplaces: cli_mps,
              ).run!
            end
          end
        end
      end
    end
  end
end
