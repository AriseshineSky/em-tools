# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonLowestOffer
      module Cli
        class DownloadAndPublish < EmTools::Core::Plugin::Cli::Base
          def banner
            <<~BANNER
              Usage: em-tools amazon-lowest-offer:coverage:download-and-publish

              Sync AMZ seed files from GCS, then publish the lowest-offer coverage snapshot.
            BANNER
          end

          def execute!(_options, argv)
            unless argv.empty?
              warn("error: unexpected arguments: #{argv.join(" ")}")
              exit(1)
            end

            EmTools::Core::Cli::Runner.run do
              EmTools::Core::PluginRegistry.fetch(:amazon_lowest_offer).download_and_publish.run!
            end
          end
        end
      end
    end
  end
end
