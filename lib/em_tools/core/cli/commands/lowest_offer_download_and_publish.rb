# frozen_string_literal: true

require "optparse"

module EmTools
  module Core
    module Cli
      module Commands
        # Convenience composite: runs +gcs-download-seeds+ then +lowest-offer-publish-snapshot+ so
        # an operator can refresh seed files and produce the snapshot in one invocation.
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
              creds_path = EmTools::Clients::GcsServiceAccountPath.require!
              target = File.join(Dir.pwd, "tmp")

              EmTools::Plugins::AmazonLowestOffer::Sources::SeedFiles.sync_from_gcs(
                target,
                marketplaces: EmTools::Plugins::AmazonLowestOffer::Queries::ListingsCoverageQuery::DEFAULT_MARKETPLACES,
                creds_path: creds_path,
                bucket: ENV.fetch("GCS_BUCKET", "em-bucket"),
                prefix: ENV.fetch("GCS_SEEDS_PREFIX", "em-analytics"),
                force: true,
              )

              publish = EmTools::Plugins::AmazonLowestOffer::Pipelines::PublishSnapshot.new.run!
              EmTools::Core::Cli::Runner::Result.new(
                summary: "Seeds synced to #{target}; #{publish.summary}",
              )
            end
          end
        end
      end
    end
  end
end
