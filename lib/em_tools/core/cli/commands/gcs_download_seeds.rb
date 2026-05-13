# frozen_string_literal: true

require "dry/cli"

module EmTools
  module Core
    module Cli
      module Commands
        # +em-tools gcs download-seeds+ — download AMZ marketplace seed files from GCS
        # into ./tmp (amz_<mp>.txt). Wraps
        # {EmTools::Plugins::AmazonLowestOffer::Sources::SeedFiles.sync_from_env!}.
        class GcsDownloadSeeds < Dry::CLI::Command
          desc "Download AMZ marketplace seed files from GCS into ./tmp/amz_<mp>.txt"

          example [
            "                                  # uses GCS_BUCKET, GCS_SEEDS_PREFIX",
          ]

          def call(**)
            EmTools::Core::Cli::Runner.run do
              target = File.join(Dir.pwd, "tmp")
              EmTools::Plugins::AmazonLowestOffer::Sources::SeedFiles.sync_from_env!(target_dir: target)
              EmTools::Core::Cli::Runner::Result.new(
                summary: "Seeds synced to #{target} (GCS objects AMZ_<MP>.txt -> amz_<mp>.txt)",
              )
            end
          end
        end
      end
    end
  end
end
