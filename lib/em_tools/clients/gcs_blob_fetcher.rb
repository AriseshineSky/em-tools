# frozen_string_literal: true

require "tempfile"
require "google/cloud/storage"

module EmTools
  module Clients
    # Resolves a service-account JSON path and downloads a single object addressed by +gs://bucket/path+.
    class GcsBlobFetcher
      def self.parse_uri(gs_uri)
        s = gs_uri.to_s.strip
        m = s.match(%r{\Ags://([^/]+)/(.+)\z}i)
        unless m
          raise ArgumentError,
            "expected gs://bucket/path/to/object, got: #{gs_uri.inspect}"
        end

        [m[1], m[2]]
      end

      def initialize(credentials_path: nil)
        @credentials_path = resolve_credentials_path(credentials_path)
        verify_credentials!
        @storage = Google::Cloud::Storage.new(credentials: @credentials_path)
      end

      # Downloads the object to a tempfile and yields its filesystem path for the duration of the block.
      def with_downloaded(gs_uri)
        bucket_name, object_path = self.class.parse_uri(gs_uri)
        bucket = @storage.bucket(bucket_name)
        raise "GCS bucket not found: #{bucket_name}" unless bucket

        remote = bucket.file(object_path)
        raise "GCS object not found: #{object_path}" unless remote

        Tempfile.create(["gcs_blob", ".bin"]) do |tmp|
          remote.download(tmp.path)
          yield tmp.path
        end
      end

      private

      def resolve_credentials_path(explicit)
        s = explicit.to_s.strip
        return File.expand_path(s) unless s.empty?

        GcsServiceAccountPath.resolve
      end

      def verify_credentials!
        return if File.file?(@credentials_path)

        raise "GCS credentials file missing: #{@credentials_path}"
      end
    end
  end
end
