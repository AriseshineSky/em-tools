# frozen_string_literal: true

module Em
  module Tools
    # Fills +ENV+ from merged settings YAML (+SettingsLoader.default_path+) only for keys that are still blank,
    # after +dotenv+ (or the shell) has run. Keeps existing rake / CLI that read +ENV+ working.
    module SettingsHydrator
      module_function

      # rubocop:disable Metrics/AbcSize -- one place to list every hydrated key.
      def apply_if_blank!
        return if ENV['EM_TOOLS_SKIP_SETTINGS_HYDRATE'].to_s == '1'
        return unless File.file?(SettingsLoader.default_path)

        h = SettingsLoader.load
        assign_if_blank('ELASTICSEARCH_URL', dig_string(h, %w[elasticsearch url]))
        assign_if_blank('REDIS_URL', dig_string(h, %w[redis url]))
        assign_if_blank('BLACKLIST_API_ENDPOINT', dig_string(h, %w[blacklist_api endpoint]))
        assign_if_blank('BLACKLIST_API_PATH', dig_string(h, %w[blacklist_api path]))
        assign_if_blank('BLACKLIST_API_KEY', dig_string(h, %w[blacklist_api api_key]))
        assign_if_blank('BLACKLIST_API_TOKEN', dig_string(h, %w[blacklist_api api_token]))
        assign_if_blank('GCS_SERVICE_ACCOUNT_PATH', dig_string(h, %w[gcs service_account_path]))
        hydrate_sites(h['sites'])
      end
      # rubocop:enable Metrics/AbcSize

      def assign_if_blank(env_key, value)
        return if ENV[env_key].to_s.strip.present?

        v = value.to_s.strip
        ENV[env_key] = v unless v.empty?
      end

      def dig_string(hash, keys)
        v = hash&.dig(*keys.map(&:to_s))
        s = v.to_s.strip
        s.empty? ? nil : s
      end

      def hydrate_sites(sites)
        return unless sites.is_a?(Hash)

        sites.each do |name, cfg|
          next unless cfg.is_a?(Hash)

          pfx = SettingsLoader.site_env_prefix(name)
          assign_if_blank("#{pfx}ENDPOINT", dig_string(cfg, %w[endpoint]))
          assign_if_blank("#{pfx}BASE_URL", dig_string(cfg, %w[base_url]))
          assign_if_blank("#{pfx}TOKEN", dig_string(cfg, %w[token]))
        end
      end
    end
  end
end
