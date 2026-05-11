# frozen_string_literal: true

module EmTools
  module Core
    module Pipelines
      # Downloads product documents from the read-only data cluster (DATA_ELASTICSEARCH_URL),
      # optionally rejecting products through the blacklist facade. Source-specific behavior is
      # selected by +config/blacklist/source_rules.yml+.
      #
      # Owns the assembly choices that the +es-download-product+ CLI shouldn't have to know:
      # which dumper to use, where to put the blocked side-file, when to call the blacklist
      # API. The CLI just maps flags to kwargs and calls +#run!+.
      class ProductDownload
        # @param blacklist_filter [Boolean]            apply the blacklist (default: on).
        # @param title_field [String]                  source field for product title.
        # @param brand_field [String]                  source field for product brand.
        # @param blocked_output_path [String, nil]     override for the blocked-products NDJSON.
        # @param env [Hash, ENV-like]                  ENV source (overridable for tests).
        def initialize(blacklist_filter: true, title_field: "title", brand_field: "brand",
          blocked_output_path: nil, env: ENV)
          @blacklist_filter = blacklist_filter
          @title_field = title_field
          @brand_field = brand_field
          @blocked_output_path = blocked_output_path
          @env = env
        end

        # @return [EmTools::Core::Cli::Runner::Result]
        def run!
          EmTools::Core::Sinks::IndexDumper
            .from_env(env: @env, prefer_data_cluster: true, **dumper_extras)
            .run!
        end

        private

        def dumper_extras
          return {} unless @blacklist_filter

          {
            policy: build_policy,
            blocked_output_path: @blocked_output_path || default_blocked_output_path,
          }
        end

        def build_policy
          keywords = EmTools::Core::Blacklist::Loader.new.fetch_keywords
          EmTools::Core::Blacklist.build(
            keywords: keywords,
            rules_source: "product_download",
            overrides: {
              "options" => {
                "title_field" => @title_field,
                "brand_field" => @brand_field,
              },
            },
          )
        end

        # +<output>.blocked.ndjson+ next to the main output, falling back to
        # +tmp/<index>.blocked.ndjson+ when +ES_DUMP_OUTPUT+ is unset.
        def default_blocked_output_path
          output = @env["ES_DUMP_OUTPUT"].to_s
          if output.empty?
            index = @env.fetch("ES_DUMP_INDEX", EmTools::Core::Sinks::IndexDumper::DEFAULT_INDEX)
            File.join("tmp", "#{index}.blocked.ndjson")
          else
            File.join(File.dirname(output), "#{File.basename(output, File.extname(output))}.blocked.ndjson")
          end
        end
      end
    end
  end
end
