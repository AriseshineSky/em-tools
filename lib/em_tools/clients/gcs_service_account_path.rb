# frozen_string_literal: true

module EmTools
  module Clients
    # Resolves the GCS JSON key path: +GCS_SERVICE_ACCOUNT_PATH+ when set, otherwise
    # +$HOME/.em_celery/gcs-sa.json+ (+Dir.home+, portable across machines).
    module GcsServiceAccountPath
      module_function

      RELATIVE_UNDER_HOME = File.join('.em_celery', 'gcs-sa.json')

      def default_path
        File.expand_path(File.join(Dir.home, RELATIVE_UNDER_HOME))
      end

      def resolve
        raw = ENV['GCS_SERVICE_ACCOUNT_PATH'].to_s.strip
        path = raw.empty? ? File.join(Dir.home, RELATIVE_UNDER_HOME) : raw
        File.expand_path(path)
      end

      # Validate the resolved key file exists. Raises {EmTools::Core::Errors::ConfigurationError}
      # with a context-aware message so rake tasks can fail fast with a clean line.
      #
      # @param env [Hash, ENV-like]
      # @param missing_message [String, nil] override for "no GCS_SERVICE_ACCOUNT_PATH set" case.
      # @return [String] resolved credentials path
      def require!(env: ENV, missing_message: nil)
        path = resolve
        return path if File.file?(path)

        if env['GCS_SERVICE_ACCOUNT_PATH'].to_s.strip.empty?
          msg = missing_message || "place your service account JSON at #{path} or set GCS_SERVICE_ACCOUNT_PATH"
          raise EmTools::Core::Errors::ConfigurationError, msg
        end

        raise EmTools::Core::Errors::ConfigurationError, "GCS_SERVICE_ACCOUNT_PATH is not a file: #{path}"
      end
    end
  end
end
