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

            argument :marketplaces,
              type: :array,
              desc: "Optional marketplace codes (e.g. us ca jp); defaults to LOWEST_OFFER_MARKETPLACES"

            example [
              "                                  # full pipeline (default markets)",
              "de us                             # subset of markets",
            ]

            def call(marketplaces: [], **)
              cli_mps = Array(marketplaces).flat_map { |a| a.to_s.split(",") }
                .map(&:strip).reject(&:empty?).map(&:downcase).join(",")
              cli_mps = nil if cli_mps.empty?

              EmTools::Core::Cli::Runner.run do
                EmTools::Core::PluginRegistry.fetch(:amazon).download_and_publish(
                  cli_marketplaces: cli_mps,
                ).run!
              end
            end
          end
        end
      end
    end
  end
end
