# frozen_string_literal: true

require "uri"

module EmTools
  module Core
    class Config
      def self.reload!
        @settings = nil
        @gcs = nil
      end

      def self.settings
        @settings ||= SettingsLoader.load
      end

      def self.elasticsearch_url
        first = string_present(ENV["ELASTICSEARCH_URL"]) ||
          dig_string(settings, ["elasticsearch", "url"])
        return first if first

        raise "ELASTICSEARCH_URL missing (set in .env or settings YAML elasticsearch.url; " \
          "see examples/config/settings.example.yml)"
      end

      # Options merged into +Elasticsearch::Client.new+ (basic auth or API key).
      #
      # When +url+ already contains credentials (+http://user:pass@host+), returns +{}+ so global
      # +ELASTICSEARCH_*+ env does not override the second cluster (+DATA_ELASTICSEARCH_URL+, etc.).
      #
      # When +url+ has no embedded credentials, optional +ELASTICSEARCH_API_KEY+ or
      # +ELASTICSEARCH_USERNAME+ / +ELASTICSEARCH_PASSWORD+ apply (primary cluster).
      def self.elasticsearch_client_arguments(url: nil)
        target = string_present(url.to_s)
        return {} if target && url_has_embedded_credentials?(target)

        api_key = string_present(ENV["ELASTICSEARCH_API_KEY"])
        if api_key
          { api_key: api_key }
        else
          user = string_present(ENV["ELASTICSEARCH_USERNAME"])
          password = string_present(ENV["ELASTICSEARCH_PASSWORD"])
          args = {}
          args[:user] = user if user
          args[:password] = password if password
          args
        end
      end

      # Resolves which cluster to talk to. When +prefer_data_cluster+ is true,
      # +DATA_ELASTICSEARCH_URL+ wins (falling back to +ELASTICSEARCH_URL+ if it is unset);
      # otherwise +ELASTICSEARCH_URL+ is used directly.
      def self.elasticsearch_connection_url(prefer_data_cluster: false)
        if prefer_data_cluster
          data_elasticsearch_url || elasticsearch_url
        else
          elasticsearch_url
        end
      end

      # One-stop factory: explicit +url+ wins, then named +cluster+, then the
      # +prefer_data_cluster+ shortcut, then the primary cluster. Credentials
      # are resolved by {EmTools::Clients::ElasticsearchClient} itself
      # (embedded user-info or +ELASTICSEARCH_USERNAME/PASSWORD/API_KEY+).
      #
      # @param url [String, nil]                explicit URL override.
      # @param cluster [String, nil]            cluster name; resolved via {.cluster_url}.
      # @param prefer_data_cluster [Boolean]    legacy shortcut for +cluster: "data"+.
      def self.elasticsearch_client(url: nil, cluster: nil, prefer_data_cluster: false)
        resolved =
          string_present(url) ||
          (string_present(cluster) ? cluster_url(cluster) : nil) ||
          elasticsearch_connection_url(prefer_data_cluster: prefer_data_cluster)
        EmTools::Clients::ElasticsearchClient.new(url: resolved)
      end

      # Resolve a logical cluster name to a concrete URL.
      #
      # - +"primary"+ (or empty / nil) -> +ELASTICSEARCH_URL+
      # - +"data"+ / +"analytics"+      -> +DATA_ELASTICSEARCH_URL+, falling back to +ELASTICSEARCH_URL+
      # - any other name               -> +ELASTICSEARCH_CLUSTER_<NAME>_URL+ env or
      #                                    +elasticsearch_clusters.<name>.url+ in YAML
      def self.cluster_url(name)
        n = name.to_s.strip
        case n
        when "", "primary"
          elasticsearch_url
        when "data", "analytics"
          data_elasticsearch_url || elasticsearch_url
        else
          elasticsearch_cluster_url(n) ||
            raise(
              EmTools::Core::Errors::ConfigurationError,
              "ES cluster #{n.inspect} not configured " \
                "(set ELASTICSEARCH_CLUSTER_#{n.upcase.tr("-", "_")}_URL or " \
                "elasticsearch_clusters.#{n}.url in settings.yml)",
            )
        end
      end

      # Named ES URLs: +ELASTICSEARCH_CLUSTER_<NAME>_URL+ (NAME uppercased, +\-+ -> +_+), then
      # +DATA_ELASTICSEARCH_URL+ for cluster names +data+ and +analytics+, then settings YAML
      # (+elasticsearch_clusters.<name>.url+).
      def self.elasticsearch_cluster_url(name)
        n = name.to_s
        pfx = "ELASTICSEARCH_CLUSTER_#{n.upcase.tr("-", "_")}_URL"
        u = string_present(ENV[pfx])
        return u if u

        if ["data", "analytics"].include?(n)
          u = string_present(ENV["DATA_ELASTICSEARCH_URL"])
          return u if u
        end

        clusters = settings["elasticsearch_clusters"]
        return unless clusters.is_a?(Hash)

        node = clusters[n]
        return unless node.is_a?(Hash)

        string_present(node["url"])
      end

      # Optional second cluster (convenience); same as +DATA_ELASTICSEARCH_URL+ env or YAML +data+ cluster.
      def self.data_elasticsearch_url
        string_present(ENV["DATA_ELASTICSEARCH_URL"]) ||
          elasticsearch_cluster_url("data") ||
          elasticsearch_cluster_url("analytics")
      end

      # Per-exporter ES URL from +exporters.<key>+: optional +url+, or +cluster+ (name in +elasticsearch_clusters+).
      # Lotteon defaults to the data cluster (+DATA_ELASTICSEARCH_URL+) when YAML has no exporter entry.
      def self.exporter_elasticsearch_url(exporter_key)
        key = exporter_key.to_s
        cfg = exporter_entry(key)

        unless cfg.nil?
          direct = string_present(cfg["url"])
          return direct if direct

          cluster = string_present(cfg["cluster"])
          if cluster
            resolved = elasticsearch_cluster_url(cluster)
            return resolved if resolved
          end
        end

        lotteon_fallback_elasticsearch_url(key)
      end

      # Index name for an exporter (+exporters.<key>.index+), or +fallback_index+ when unset.
      def self.exporter_index(exporter_key, fallback_index)
        cfg = exporter_entry(exporter_key.to_s)
        return fallback_index if cfg.nil?

        string_present(cfg["index"]) || fallback_index
      end

      def self.redis_url
        string_present(ENV["REDIS_URL"]) || dig_string(settings, ["redis", "url"])
      end

      # Blacklist API config is .env-only; YAML must not carry these secrets.
      def self.blacklist_api_endpoint
        string_present(ENV["BLACKLIST_API_ENDPOINT"])
      end

      def self.blacklist_api_path
        string_present(ENV["BLACKLIST_API_PATH"])
      end

      def self.blacklist_api_token
        string_present(ENV["BLACKLIST_API_TOKEN"])
      end

      # --- Cloud Translation (Basic / v2) — optional caps in YAML + .env overrides ---
      #
      # Billing is per **source character**; {EmTools::Core::Translation::BudgetedTranslator}
      # enforces caps. When +max_billable_chars+ resolves to 0, translation is treated as disabled.
      def self.translate_settings
        s = settings["translate"]
        s.is_a?(Hash) ? s : {}
      end

      def self.translate_max_billable_chars
        integer_setting(
          ENV["EM_TRANSLATE_MAX_CHARS"],
          translate_settings["max_billable_chars"],
          default: 0,
        )
      end

      def self.translate_daily_char_cap
        integer_setting(
          ENV["EM_TRANSLATE_DAILY_CAP"],
          translate_settings["daily_char_cap"],
          default: 0,
        )
      end

      def self.translate_state_path
        string_present(ENV["EM_TRANSLATE_STATE_PATH"]) ||
          string_present(translate_settings["state_path"]) ||
          File.join("tmp", "translate_usage_state.json")
      end

      def self.translate_cache_dir
        string_present(ENV["EM_TRANSLATE_CACHE_DIR"]) ||
          string_present(translate_settings["cache_dir"])
      end

      def self.translate_min_interval_seconds
        float_setting(
          ENV["EM_TRANSLATE_MIN_INTERVAL"],
          translate_settings["min_interval_seconds"],
          default: 0.35,
        )
      end

      def self.translate_max_chars_per_request
        integer_setting(
          ENV["EM_TRANSLATE_MAX_PER_REQUEST"],
          translate_settings["max_chars_per_request"],
          default: 4500,
        )
      end

      def self.translate_max_retries
        integer_setting(
          ENV["EM_TRANSLATE_MAX_RETRIES"],
          translate_settings["max_retries"],
          default: 3,
        )
      end

      # Path to a GCS service account JSON key (optional; used by gcs rake tasks /
      # +EmTools::Clients::GcsHelper+). When +GCS_SERVICE_ACCOUNT_PATH+ is unset, defaults to
      # +~/.em_celery/gcs-sa.json+.
      def self.gcs_service_account_path
        EmTools::Clients::GcsServiceAccountPath.resolve
      end

      # Per-site HTTP settings from +sites.<name>+ in settings.yml, overridden by
      # +EM_TOOLS_SITE_<NAME>_ENDPOINT+, +_BASE_URL+, +_TOKEN+ (NAME is upcased, +-+ -> +_+). # -- small merge of three keys from YAML vs ENV.
      def self.site(name)
        key = name.to_s
        sites = settings["sites"]
        y = sites.is_a?(Hash) ? sites[key] : nil
        y = {} unless y.is_a?(Hash)
        pfx = SettingsLoader.site_env_prefix(key)
        {
          "base_url" => string_present(ENV["#{pfx}BASE_URL"]) || dig_string(y, ["base_url"]),
          "endpoint" => string_present(ENV["#{pfx}ENDPOINT"]) || dig_string(y, ["endpoint"]),
          "token" => string_present(ENV["#{pfx}TOKEN"]) || dig_string(y, ["token"]),
        }.compact
      end
      # rubocop:enable Metrics/AbcSize

      def self.gcs
        @gcs ||= Gcs.new
      end

      def self.string_present(str)
        s = str.to_s.strip
        s.empty? ? nil : s
      end

      def self.dig_string(hash, keys)
        v = hash&.dig(*keys.map(&:to_s))
        s = v.to_s.strip
        s.empty? ? nil : s
      end

      private_class_method :string_present, :dig_string

      def self.exporter_entry(key)
        map = settings["exporters"]
        return unless map.is_a?(Hash)

        entry = map[key.to_s]
        entry.is_a?(Hash) ? entry : nil
      end

      def self.lotteon_fallback_elasticsearch_url(exporter_key)
        return data_elasticsearch_url || elasticsearch_url if exporter_key.to_s == "lotteon_products"

        elasticsearch_url
      end

      private_class_method :exporter_entry, :lotteon_fallback_elasticsearch_url

      def self.url_has_embedded_credentials?(url_string)
        uri = URI.parse(url_string.to_s)
        uri.user && !uri.user.empty?
      rescue URI::InvalidURIError
        false
      end
      private_class_method :url_has_embedded_credentials?

      def self.integer_setting(env_val, yaml_val, default:)
        v = string_present(env_val) || yaml_val&.to_s&.strip
        return default if v.nil? || v.empty?

        Integer(v)
      rescue ArgumentError
        default
      end
      private_class_method :integer_setting

      def self.float_setting(env_val, yaml_val, default:)
        v = string_present(env_val) || yaml_val&.to_s&.strip
        return default if v.nil? || v.empty?

        Float(v)
      rescue ArgumentError
        default
      end
      private_class_method :float_setting

      # GCS bucket name routing from merged settings (+gcs.buckets+). Project ID and
      # credentials path are NEVER read from YAML — use +.env+ +GCS_PROJECT_ID+ /
      # +GCS_SERVICE_ACCOUNT_PATH+ / +GCS_CREDENTIALS+ instead.
      class Gcs
        def initialize
          @buckets = load_buckets
        end

        def project_id
          present(ENV["GCS_PROJECT_ID"])
        end

        def credentials
          present(ENV["GCS_CREDENTIALS"]) || present(Config.gcs_service_account_path)
        end

        def bucket(name = :inventory)
          value = @buckets[name.to_s] || @buckets[name.to_sym]
          value or raise "GCS bucket not found: #{name}"
        end

        private

        def present(str)
          s = str.to_s.strip
          s.empty? ? nil : s
        end

        def load_buckets
          gcs = EmTools::Core::Config.settings["gcs"]
          buckets = gcs.is_a?(Hash) ? gcs["buckets"] : nil
          unless buckets.is_a?(Hash) && !buckets.empty?
            raise "GCS config missing: add gcs.buckets to your settings YAML " \
              "(see examples/config/settings.example.yml)"
          end

          buckets.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
        end
      end
    end
  end
end
