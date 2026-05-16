# frozen_string_literal: true

module EmTools
  module Plugins
    module Lazada
      # Lazada multi-marketplace exports (TH / MY / custom YAML profiles).
      #
      # Routing and formatter defaults live under +lazada_marketplaces+ and +exporters.*+
      # in settings — see {MarketplaceProfile}.
      class Plugin < EmTools::Core::Plugin::Base
        def self.plugin_name = :lazada

        EmTools::Core::PluginRegistry.register(plugin_name, self)

        def capabilities
          {
            products: {
              exporter: Exporters::ProductsExporter,
              query: Queries::ProductsQuery,
            },
          }
        end

        def dependencies
          @dependencies ||= {
            es_client: EmTools::Clients::ElasticsearchClient.new(
              url: EmTools::Core::Config.exporter_elasticsearch_url("lazada_th_products"),
            ),
          }
        end

        def cli_commands
          {
            "products export" => Cli::ExportProducts,
            "products build-upload" => Cli::BuildUpload,
          }
        end

        # @param marketplace [String] +"th"+, +"my"+, or a custom key under +lazada_marketplaces+
        # @param client [EmTools::Clients::ElasticsearchClient, nil] defaults from profile exporter URL
        # @param elasticsearch_url [String, nil] overrides ES URL when building client
        # @param source_value [String, nil] overrides profile +products_query.source_value+
        # @param apply_keyword_policy [Boolean]
        # @param rules_source [String, nil] blacklist YAML rule id (default from profile)
        # @param for_upload [Boolean]
        # @param translation_merge_index [String, nil] when non-empty, merge +title_en+ from this index
        def products_exporter(marketplace:, client: nil, elasticsearch_url: nil, source_value: nil,
          apply_keyword_policy: false, keywords: nil, rules_source: nil,
          blocked_output_path: nil,
          title_field: nil, brand_field: nil,
          converter: nil, for_upload: false,
          inventory_source: nil,
          validate_for_upload: true, logger: nil,
          translation_merge_index: nil, translation_elasticsearch_url: nil,
          translation_merge: true,
          translation_source_field: nil, translation_source_product_id_field: nil,
          **_opts)
          profile = MarketplaceProfile.fetch(marketplace)

          resolved_client =
            client ||
            EmTools::Clients::ElasticsearchClient.new(
              url: pick_url(elasticsearch_url, profile.elasticsearch_base_url),
            )

          sv = string_pick(source_value, profile.products_query_source_value)
          query = Queries::ProductsQuery.new(
            source_value: sv,
            source_field: profile.products_query_source_field,
            extra_filters: profile.extra_es_filters,
          )

          policy =
            if apply_keyword_policy
              build_keyword_policy(
                keywords: keywords,
                title_field: string_pick(title_field, profile.title_field),
                brand_field: string_pick(brand_field, profile.brand_field),
                rules_source: string_pick(rules_source, profile.keyword_rules_source),
              )
            end

          resolved_converter =
            if converter
              converter
            elsif for_upload
              Formatting::ProductExportFormatter.build_for_profile(
                profile,
                logger: logger,
                validate: validate_for_upload,
                inventory_source_override: inventory_source,
              )
            end

          tr_idx = translation_merge_index.to_s.strip
          if translation_merge && resolved_converter && !tr_idx.empty?
            tr_url = string_pick(translation_elasticsearch_url, profile.translation_elasticsearch_url)
            resolved_converter = EmTools::Core::Translation::TitleEnFromTranslationIndex.compose_with(
              inner: resolved_converter,
              product_es_client: resolved_client,
              translation_index: tr_idx,
              translation_elasticsearch_url: tr_url,
              translation_source_field: string_pick(translation_source_field, profile.translation_source_field),
              translation_source_product_id_field:
                string_pick(translation_source_product_id_field, profile.translation_source_product_id_field),
            )
          end

          capabilities.dig(:products, :exporter).new(
            client: resolved_client,
            index: profile.elasticsearch_index_name,
            query: query,
            policy: policy,
            blocked_output_path: apply_keyword_policy ? blocked_output_path : nil,
            converter: resolved_converter,
            logger: logger,
          )
        end

        private

        def pick_url(primary, fallback)
          p = primary.to_s.strip
          p.empty? ? fallback : p
        end

        def string_pick(primary, fallback)
          p = primary.to_s.strip
          p.empty? ? fallback.to_s : p
        end

        def build_keyword_policy(keywords:, title_field:, brand_field:, rules_source:)
          words = (keywords && Array(keywords)) || EmTools::Core::Blacklist::Loader.new.fetch_keywords
          EmTools::Core::Blacklist.build(
            keywords: words,
            rules_source: rules_source,
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
