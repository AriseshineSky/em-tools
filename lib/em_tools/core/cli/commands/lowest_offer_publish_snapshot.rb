# frozen_string_literal: true

require "optparse"

module EmTools
  module Core
    module Cli
      module Commands
        # Lowest-offer monitoring snapshot: queries Amazon coverage for the configured ASIN list
        # and writes a coverage document per marketplace into ES.
        class LowestOfferPublishSnapshot
          def run(argv)
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools lowest-offer-publish-snapshot [marketplace ...]

                Publish lowest-offer coverage snapshot to Elasticsearch.
                Optional arguments: marketplace codes (e.g. us ca jp or us,ca); otherwise
                LOWEST_OFFER_MARKETPLACES or default nine markets.

                See LOWEST_OFFER_* env vars (.env.example).
              BANNER
              opts.on_tail("-h", "--help") do
                puts opts
                exit(0)
              end
            end
            parser.parse!(argv)

            cli_mps =
              argv.flat_map { |a| a.split(",") }.map(&:strip).reject(&:empty?).map(&:downcase).join(",")
            cli_mps = nil if cli_mps.empty?

            EmTools::Core::Cli::Runner.run do
              EmTools::Plugins::AmazonLowestOffer::Pipelines::PublishSnapshot.new(
                cli_marketplaces: cli_mps,
              ).run!
            end
          end
        end
      end
    end
  end
end
