# frozen_string_literal: true

require "fileutils"

module EmTools
  module Plugins
    module Amazon
      module LowestOffer
        module Pipelines
          # Convenience composite: refresh AMZ marketplace seed files from GCS, then publish the
          # lowest-offer coverage snapshot. This is the only piece of "do both steps" workflow
          # knowledge that used to live in the +lowest-offer-download-and-publish+ CLI.
          #
          # Constructable directly (cron / scheduler / another plugin) and from the CLI
          # without re-stating the seed-sync defaults or the summary-stitching rule.
          class DownloadAndPublish
            # @param target_dir [String] where seed files land; defaults to +./tmp+.
            # @param env [Hash, ENV-like]
            # @param snapshot [#run!] override for {PublishSnapshot} (mainly for tests).
            def initialize(target_dir: nil, env: ENV, snapshot: nil)
              @target_dir = target_dir || File.join(Dir.pwd, "tmp")
              @env = env
              @snapshot = snapshot || PublishSnapshot.new
            end

            # @return [EmTools::Core::Cli::Runner::Result]
            def run!
              Sources::SeedFiles.sync_from_env!(target_dir: @target_dir, env: @env)
              publish = @snapshot.run!
              EmTools::Core::Cli::Runner::Result.new(
                summary: "Seeds synced to #{@target_dir}; #{publish.summary}",
              )
            end
          end
        end
      end
    end
  end
end
