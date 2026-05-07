# frozen_string_literal: true

module Em
  module Tools
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
    end
  end
end
