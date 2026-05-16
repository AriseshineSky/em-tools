# frozen_string_literal: true

require "fileutils"

module EmTools
  module Plugins
    module Amazon
      module LowestOffer
        module Sources
          # Syncs local +amz_<mp>.txt+ seeds from GCS (+<prefix>/sources/AMZ_<MP>.txt+).
          class SeedFiles
            def self.seed_file_present?(dir, mp)
              mp = mp.to_s.downcase
              File.file?(File.join(dir, "amz_#{mp}.txt")) || File.file?(File.join(dir, "ebay_#{mp}.txt"))
            end

            # Writes +dir+/+amz_<mp>.txt+ for each marketplace (lowercase +mp+ in filename).
            # When +force+ is false, skips marketplaces that already have +amz_+ or +ebay_+ seed file.
            # When +force+ is true, always re-downloads from GCS and overwrites +amz_<mp>.txt+.
            def self.sync_from_gcs(dir, marketplaces:, creds_path:, bucket:, prefix:, force: false)
              FileUtils.mkdir_p(dir)
              pfx = prefix.to_s.sub(%r{/+\z}, "")
              helper = EmTools::Clients::GcsHelper.new(creds_path, bucket, pfx)

              marketplaces.each do |mp|
                mpd = mp.to_s.downcase
                next if !force && seed_file_present?(dir, mpd)

                blob = "#{pfx}/sources/AMZ_#{mpd.upcase}.txt"
                local = File.join(dir, "amz_#{mpd}.txt")
                helper.download_file(blob, local)
              end
            end

            # Env-driven entrypoint used by +gcs-download-seeds+ and any composite pipeline that
            # wants "refresh seeds from GCS" without restating the bucket/prefix/creds defaults.
            # Always runs with +force: true+ because the consumers want a fresh snapshot.
            #
            # @param target_dir [String]
            # @param env [Hash, ENV-like]
            # @param marketplaces [Array<String>, nil] +nil+ defaults to the lowest-offer plugin's
            #   canonical marketplace list.
            # @return [String] +target_dir+ for chaining.
            def self.sync_from_env!(target_dir:, env: ENV, marketplaces: nil)
              creds_path = EmTools::Clients::GcsServiceAccountPath.require!
              sync_from_gcs(
                target_dir,
                marketplaces: marketplaces || Queries::ListingsCoverageQuery::DEFAULT_MARKETPLACES,
                creds_path: creds_path,
                bucket: env.fetch("GCS_BUCKET", "em-bucket"),
                prefix: env.fetch("GCS_SEEDS_PREFIX", "em-analytics"),
                force: true,
              )
              target_dir
            end
          end
        end
      end
    end
  end
end
