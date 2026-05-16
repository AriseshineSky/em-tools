# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Plugins
    module Amazon
      module LowestOffer
        module Cli
          # +em-tools amazon coverage publish-snapshot [marketplace ...]+ —
          # publish lowest-offer coverage to Elasticsearch, optionally constrained to a
          # subset of marketplaces.
          class PublishSnapshot < Dry::CLI::Command
            desc "Publish lowest-offer coverage snapshot to Elasticsearch"

            argument :marketplaces,
              type: :array,
              desc: "Optional marketplace codes (e.g. us ca jp); defaults to LOWEST_OFFER_MARKETPLACES"

            example [
              "                                  # default markets",
              "us ca jp                          # subset of markets",
            ]

            def call(marketplaces: [], **)
              cli_mps = Array(marketplaces).flat_map { |a| a.to_s.split(",") }
                .map(&:strip).reject(&:empty?).map(&:downcase).join(",")
              cli_mps = nil if cli_mps.empty?

              EmTools::Core::Cli::Runner.run do
                EmTools::Core::PluginRegistry.fetch(:amazon).publish_snapshot(
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
