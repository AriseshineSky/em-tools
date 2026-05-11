# frozen_string_literal: true

require "optparse"

module EmTools
  module Core
    module Cli
      module Commands
        # Download lowest-offer AMZ seed files from GCS into +./tmp/+.
        class GcsDownloadSeeds
          def run(argv)
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools gcs-download-seeds

                Download AMZ marketplace seed files from GCS into ./tmp (amz_<mp>.txt).
                Requires GCS_SERVICE_ACCOUNT_PATH (or default credentials).

                Env: GCS_BUCKET (default em-bucket), GCS_SEEDS_PREFIX (default em-analytics).
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
