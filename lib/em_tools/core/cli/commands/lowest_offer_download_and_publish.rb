# frozen_string_literal: true

require "optparse"

module EmTools
  module Core
    module Cli
      module Commands
        # Thin CLI wrapper over
        # {EmTools::Plugins::AmazonLowestOffer::Pipelines::DownloadAndPublish}.
        class LowestOfferDownloadAndPublish
          def run(argv)
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools lowest-offer-download-and-publish

                Runs gcs-download-seeds then lowest-offer-publish-snapshot (default marketplaces).
              BANNER
              opts.on_tail("-h", "--help") do
                puts opts
                exit(0)
              end
            end
            parser.parse!(argv)

            unless argv.empty?
              warn("error: unexpected arguments: #{argv.join(" ")}")
              exit(1)
            end

            EmTools::Core::Cli::Runner.run do
              EmTools::Plugins::AmazonLowestOffer::Pipelines::DownloadAndPublish.new.run!
            end
          end
        end
      end
    end
  end
end
