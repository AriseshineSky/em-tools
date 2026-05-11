# frozen_string_literal: true

require "optparse"

module EmTools
  module Core
    module Cli
      module Commands
        # eBay listings coverage snapshot: queries eBay for the current ASIN list and writes a
        # one-row-per-marketplace coverage document into ES.
        class EbayListingsPublishSnapshot
          def run(argv)
            parser = OptionParser.new do |opts|
              opts.banner = <<~BANNER
                Usage: em-tools ebay-listings-publish-snapshot [marketplace]

                Publish eBay listings coverage snapshot. Optional marketplace argument (e.g. us);
                otherwise EBAY_LISTINGS_COVERAGE_MARKETPLACE or default us.

                See EBAY_LISTINGS_COVERAGE_* env vars (.env.example).
              BANNER
              opts.on_tail("-h", "--help") do
                puts opts
                exit(0)
              end
            end
            parser.parse!(argv)

            mp = argv.shift
            unless argv.empty?
              warn("error: unexpected arguments: #{argv.join(" ")}")
              exit(1)
            end

            EmTools::Core::Cli::Runner.run do
              EmTools::Plugins::Ebay::Pipelines::PublishSnapshot.new(cli_marketplace: mp).run!
            end
          end
        end
      end
    end
  end
end
