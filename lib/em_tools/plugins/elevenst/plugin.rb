# frozen_string_literal: true

module EmTools
  module Plugins
    module Oliveyoung
      # Korean marketplace - Oliveyoung. Bundles the products NDJSON exporter
      # (filtered to +source=oliveyoung+ via {Queries::ProductsQuery}) and the
      # keyword scanner.
      #
      # == Keyword exclusion policy
      #
      # The exporter accepts an optional +policy+ (see
      # {Exporters::ProductsExporter}). The +products_exporter+ factory below
      # is the place where that policy is assembled from the
      # {EmTools::Core::Blacklist} facade — see
      # +docs/DDD_AND_UBIQUITOUS_LANGUAGE.md+ for why we keep the upstream
      # name "blacklist" at the boundary while talking about a
      # "禁售关键词 / keyword exclusion policy" in plugin-internal code.
      class Plugin < EmTools::Core::Plugin::Base
        def self.plugin_name = :oliveyoung

        EmTools::Core::PluginRegistry.register(plugin_name, self)

        def capabilities
          {
            products: {
              exporter: Exporters::ProductsExporter,
              query: Queries::ProductsQuery,
              scanner: Scanners::ProductsScanner,
            },
          }
        end

        def dependencies
          @dependencies ||= {
            es_client: EmTools::Clients::ElasticsearchClient.new(
              url: EmTools::Core::Config.exporter_elasticsearch_url(Exporters::ProductsExporter::EXPORTER_KEY),
            ),
          }
        end

        def cli_commands
          {
            "products export" => Cli::ExportProducts,
            "products build-upload" => Cli::BuildStoreUpload,
          }
        end

        # Factory: returns a configured exporter.
        #
        # The +source=oliveyoung+ filter is wired in via the default query.
        #
        # Keyword exclusion is **opt-in**: pass +apply_keyword_policy: true+
        # (CLI default) to assemble a {Core::Blacklist::Strategy::TitleBrand}
        # policy. Keywords come from +keywords+ if given, otherwise from the
        # admin API via {Core::Blacklist::Loader}.
        #
        # @param client [EmTools::Clients::ElasticsearchClient]
        # @param source_value [String, nil] override the +source+ term value.
        # @param apply_keyword_policy [Boolean] wire the prohibited-keyword
        #   filter into the exporter (default: false; CLI sets it).
        # @param keywords [Array<String>, nil] preloaded keyword list (e.g.
        #   from +--keywords-path+); skips the admin API call.
        # @param blocked_output_path [String, nil] write rejected docs here as
        #   NDJSON; ignored without +apply_keyword_policy+.
        # @param title_field [String], brand_field [String]
        # @param converter [#call, nil] optional; +.call(es_source)+ per written line
        #   (see {Exporters::ProductsExporter}).
        # @param for_upload [Boolean] when true and +converter+ is omitted, wires
        #   {Formatting::ProductExportFormatter} (same role as +format_oliveyoung.py+).
        # @param inventory_source [String] Spree inventory source for uploaded-ID skip.
        # @param validate_for_upload [Boolean] run {EmProduct::StandardProduct} when +for_upload+.
        # @param logger [::Logger, nil] passed to the exporter and upload converter.
        # @param translation_index [String, nil] when set, merge +title_en+ from this ES index
        #   (see {EmTools::Core::Translation::TitleEnFromTranslationIndex}) before any +converter+.
        # @param translation_elasticsearch_url [String, nil] optional cluster URL for the translation index
        # @param translation_source_field [String] source key field on the product doc (default +source+)
        # @param translation_source_product_id_field [String] default +source_product_id+
        def products_exporter(client: dependencies[:es_client], source_value: nil,
          apply_keyword_policy: false, keywords: nil,
          blocked_output_path: nil,
          title_field: "title", brand_field: "brand",
          converter: nil, for_upload: false, inventory_source: "oliveyoung",
          validate_for_upload: true, logger: nil,
          translation_index: nil, translation_elasticsearch_url: nil,
          translation_source_field: "source", translation_source_product_id_field: "source_product_id",
          **_opts)
          query = source_value ? Queries::ProductsQuery.new(source_value: source_value) : nil
          policy =
            if apply_keyword_policy
              build_keyword_policy(keywords: keywords, title_field: title_field, brand_field: brand_field)
            end

          resolved_converter =
            if converter
              converter
            elsif for_upload
              Formatting::ProductExportFormatter.build(
                inventory_source: inventory_source,
                logger: logger,
                validate: validate_for_upload,
              )
            end

          resolved_converter = EmTools::Core::Translation::TitleEnFromTranslationIndex.compose_with(
            inner: resolved_converter,
            product_es_client: client,
            translation_index: translation_index,
            translation_elasticsearch_url: translation_elasticsearch_url,
            translation_source_field: translation_source_field,
            translation_source_product_id_field: translation_source_product_id_field,
          )

          capabilities.dig(:products, :exporter).new(
            client: client,
            query: query,
            policy: policy,
            blocked_output_path: apply_keyword_policy ? blocked_output_path : nil,
            converter: resolved_converter,
            logger: logger,
          )
        end

        def products_scanner(**opts)
          capabilities.dig(:products, :scanner).new(**opts)
        end

        private

        # Boundary mapping: the upstream Everymarket admin API is named
        # "blacklist API"; we keep that name on the +Loader+ but expose the
        # composed object under the more accurate domain name (a "keyword
        # exclusion policy") to the rest of the plugin.
        def build_keyword_policy(keywords:, title_field:, brand_field:)
          words = (keywords && Array(keywords)) || EmTools::Core::Blacklist::Loader.new.fetch_keywords
          EmTools::Core::Blacklist.build(
            keywords: words,
            rules_source: "product_download",
            overrides: {
              "options" => {
                "title_field" => title_field,
                "brand_field" => brand_field,
              },
            },
          )
        end
      end
    end
  end
end
