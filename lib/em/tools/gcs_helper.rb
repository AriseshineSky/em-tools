# frozen_string_literal: true

require 'fileutils'
require 'google/cloud/storage'

module Em
  module Tools
    # Downloads objects from a GCS bucket using a service account JSON key.
    # +prefix+ is reserved for API parity with other tooling; object names passed to
    # #download_file should be full paths within the bucket (e.g. em-analytics/sources/AMZ_US.txt).
    #
    # Transfers use the Storage API's streaming download (chunked HTTP body written to the
    # destination); data is not buffered entirely in memory for the download itself.
    class GcsHelper
      def initialize(credentials_path, bucket_name, _prefix = nil)
        @bucket_name = bucket_name
        @storage = Google::Cloud::Storage.new(credentials: credentials_path)
      end

      # Writes +blob_name+ to +local_path+ using a streaming download into an open file IO.
      # +verify+ is passed to the client (:md5 default, :crc32c, :all, or :none).
      def download_file(blob_name, local_path, verify: :md5)
        FileUtils.mkdir_p(File.dirname(local_path))

        bucket = @storage.bucket(@bucket_name)
        raise "GCS bucket not found: #{@bucket_name}" unless bucket

        remote = bucket.file(blob_name)
        raise "GCS object not found: #{blob_name}" unless remote

        File.open(local_path, 'wb') do |io|
          remote.download(io, verify: verify)
        end
      end
    end
  end
end
