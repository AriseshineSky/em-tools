# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Amazon
      module LowestOffer
        module Cli
          # +em-tools amazon coverage download-and-publish+ — sync AMZ seed
          # files from GCS, then publish the lowest-offer coverage snapshot.
          class DownloadAndPublish < Dry::CLI::Command
            desc "Sync AMZ seed files from GCS, then publish coverage snapshot"

            example [
              "                                  # full pipeline (default markets)",
            ]

            def call(**)
              EmTools::Core::Cli::Runner.run do
                EmTools::Core::PluginRegistry.fetch(:amazon).download_and_publish.run!
              end
            end
          end
        end
      end
    end
  end
end
