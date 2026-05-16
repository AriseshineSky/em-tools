# frozen_string_literal: true

module EmTools
  module Plugins
    module Lazada
      # Loads per-marketplace routing + formatter knobs from merged settings under
      # +lazada_marketplaces.<code>+, merged with built-in defaults for +th+ and +my+.
      #
      # Each marketplace points at an +exporters.<exporter_key>+ entry for ES URL + index.
      class MarketplaceProfile
        MARKETPLACE_DEFAULTS = {
          "th" => {
            "exporter_key" => "lazada_th_products",
            "inventory_source" => "lazadacoth",
            "display_source" => "Lazada TH",
            "sku_prefix" => "LZ-TH-",
            "keyword_filter_default" => true,
            "translate_by_default" => false,
            "translation_index" => nil,
            "translation_elasticsearch_url" => nil,
            "translation_source_field" => "source",
            "translation_source_product_id_field" => "source_product_id",
            "title_field" => "title",
            "brand_field" => "brand",
            "keyword_rules_source" => "product_download",
            "products_query" => {
              "source_field" => "source",
              "source_value" => nil,
            },
            "price_rules" => {
              "roi" => 0.3,
              "ad_cost" => 4.5,
              "transfer_cost" => 0,
            },
            "formatter_filters" => {
              "skip_multi_variant" => true,
              "skip_options" => true,
              "skip_already_uploaded" => true,
            },
            "extra_es_filters" => [],
          },
          "my" => {
            "exporter_key" => "lazada_my_products",
            "inventory_source" => "lazadamys",
            "display_source" => "Lazada MY",
            "sku_prefix" => "LZ-MY-",
            "keyword_filter_default" => true,
            "translate_by_default" => false,
            "translation_index" => nil,
            "translation_elasticsearch_url" => nil,
            "translation_source_field" => "source",
            "translation_source_product_id_field" => "source_product_id",
            "title_field" => "title",
            "brand_field" => "brand",
            "keyword_rules_source" => "product_download",
            "products_query" => {
              "source_field" => "source",
              "source_value" => nil,
            },
            "price_rules" => {
              "roi" => 0.28,
              "ad_cost" => 4.5,
              "transfer_cost" => 0,
            },
            "formatter_filters" => {
              "skip_multi_variant" => true,
              "skip_options" => true,
              "skip_already_uploaded" => true,
            },
            "extra_es_filters" => [],
          },
        }.freeze

        class << self
          # @param code [String] e.g. +"th"+, +"my"+
          # @return [MarketplaceProfile]
          # @raise [EmTools::Core::Errors::ConfigurationError]
          def fetch(code)
            key = code.to_s.strip.downcase
            raise EmTools::Core::Errors::ConfigurationError, "lazada marketplace code is blank" if key.empty?

            yaml_root = EmTools::Core::Config.settings["lazada_marketplaces"]
            yaml_node = yaml_root.is_a?(Hash) ? yaml_root[key] : nil
            yaml_hash = yaml_node.is_a?(Hash) ? stringify_keys_deep(yaml_node) : {}

            base = MARKETPLACE_DEFAULTS[key] || MARKETPLACE_DEFAULTS["th"]
            merged = deep_merge_hashes(base, yaml_hash)
            new(code: key, hash: merged)
          end

          private

          def deep_merge_hashes(a, b)
            a.merge(b) do |_, old_v, new_v|
              if old_v.is_a?(Hash) && new_v.is_a?(Hash)
                deep_merge_hashes(old_v, new_v)
              elsif old_v.is_a?(Array) && new_v.is_a?(Array)
                new_v
              else
                new_v.nil? ? old_v : new_v
              end
            end
          end

          def stringify_keys_deep(obj)
            case obj
            when Hash
              obj.each_with_object({}) do |(k, v), acc|
                acc[k.to_s] = stringify_keys_deep(v)
              end
            when Array
              obj.map { |x| stringify_keys_deep(x) }
            else
              obj
            end
          end
        end

        attr_reader :code

        def initialize(code:, hash:)
          @code = code
          @h = hash
        end

        def exporter_key
          @h.fetch("exporter_key").to_s
        end

        def inventory_source
          @h.fetch("inventory_source").to_s
        end

        def display_source
          @h.fetch("display_source").to_s
        end

        def sku_prefix
          @h.fetch("sku_prefix").to_s
        end

        def keyword_filter_default?
          !!@h["keyword_filter_default"]
        end

        def translate_by_default?
          !!@h["translate_by_default"]
        end

        def translation_index
          v = @h["translation_index"]
          v.nil? || v.to_s.strip.empty? ? nil : v.to_s.strip
        end

        def translation_elasticsearch_url
          v = @h["translation_elasticsearch_url"]
          v.nil? || v.to_s.strip.empty? ? nil : v.to_s.strip
        end

        def translation_source_field
          @h.fetch("translation_source_field").to_s
        end

        def translation_source_product_id_field
          @h.fetch("translation_source_product_id_field").to_s
        end

        def title_field
          @h.fetch("title_field").to_s
        end

        def brand_field
          @h.fetch("brand_field").to_s
        end

        def keyword_rules_source
          @h.fetch("keyword_rules_source").to_s
        end

        def products_query_source_field
          pq = @h["products_query"]
          return "source" unless pq.is_a?(Hash)

          pq.fetch("source_field", "source").to_s
        end

        # @return [String, nil] nil or blank => match_all (no term on source)
        def products_query_source_value
          pq = @h["products_query"]
          return unless pq.is_a?(Hash)

          v = pq["source_value"]
          s = v.to_s.strip
          s.empty? ? nil : s
        end

        # @return [Hash] string-keyed merge target for PriceCalculator
        def price_rules_hash
          pr = @h["price_rules"]
          pr.is_a?(Hash) ? pr : {}
        end

        def formatter_filters_hash
          ff = @h["formatter_filters"]
          ff.is_a?(Hash) ? ff : {}
        end

        def skip_multi_variant?
          v = formatter_filters_hash["skip_multi_variant"]
          v.nil? ? true : !!v
        end

        def skip_options?
          v = formatter_filters_hash["skip_options"]
          v.nil? ? true : !!v
        end

        def skip_already_uploaded?
          v = formatter_filters_hash["skip_already_uploaded"]
          v.nil? ? true : !!v
        end

        # @return [Array<Hash>] raw ES bool.filter clauses from YAML
        def extra_es_filters
          xs = @h["extra_es_filters"]
          return [] unless xs.is_a?(Array)

          xs.grep(Hash)
        end

        def elasticsearch_index_name
          EmTools::Core::Config.exporter_index(exporter_key, fallback_index_for(exporter_key))
        end

        def elasticsearch_base_url
          EmTools::Core::Config.exporter_elasticsearch_url(exporter_key)
        end

        private

        def fallback_index_for(exporter_key)
          case exporter_key.to_s
          when "lazada_th_products", "lazada_products"
            "user1_lazadacoth_products"
          when "lazada_my_products"
            "user1_lazadamys_products"
          else
            "user1_lazadacoth_products"
          end
        end
      end
    end
  end
end
