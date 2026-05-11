# frozen_string_literal: true

require "fileutils"

module EmTools
  module Plugins
    module AmazonLowestOffer
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
        end
      end
    end
  end
end
