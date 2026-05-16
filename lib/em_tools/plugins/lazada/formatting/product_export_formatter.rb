# frozen_string_literal: true

require "json"
require "set"
require "product_validator"

module EmTools
  module Plugins
    module Lazada
      module Formatting
        # Shapes Lazada ES product documents into storefront-upload rows.
        # Behavior is driven by {MarketplaceProfile} (display label, SKU prefix,
        # price rules, and which upload guards run).
        class ProductExportFormatter
          SKIP = :skip

          DEFAULT_PRICE_RULES = {
            "roi" => 0.3,
            "ad_cost" => 4.5,
            "transfer_cost" => 0,
          }.freeze

          # @param uploaded_product_ids [Set<String>]
          # @param display_source [String] storefront +source+ label (e.g. +"Lazada TH"+)
          # @param sku_prefix [String] prefix before +product_id+
          # @param price_rules [Hash] passed to {Amazon::Uploadable::Transforms::PriceCalculator}
          # @param skip_multi_variant [Boolean]
          # @param skip_options [Boolean]
          # @param skip_already_uploaded [Boolean]
          def initialize(uploaded_product_ids:, price_calculator: nil, price_formatter: nil,
            logger: nil, validate: true,
            display_source: "Lazada TH", sku_prefix: "LZ-TH-",
            price_rules: nil,
            skip_multi_variant: true, skip_options: true, skip_already_uploaded: true)
            @uploaded = uploaded_product_ids
            @logger = logger || EmTools::Core::Logger.for(progname: "lazada-product-export")
            @validate = validate
            @display_source = display_source.to_s
            @sku_prefix = sku_prefix.to_s
            @skip_multi_variant = skip_multi_variant
            @skip_options = skip_options
            @skip_already_uploaded = skip_already_uploaded
            rules = price_rules.is_a?(Hash) ? DEFAULT_PRICE_RULES.merge(price_rules) : DEFAULT_PRICE_RULES
            @calc = price_calculator || default_price_calculator(rules)
            @price_formatter = price_formatter || EmTools::Core::ProductFormatting::PriceFormatter.new(
              price_calculator: @calc,
            )
          end

          # @param inventory_source [String]
          # @param profile [MarketplaceProfile, nil]
          def self.build(inventory_source:, logger: nil, validate: true, profile: nil,
            display_source: nil, sku_prefix: nil, price_rules: nil,
            skip_multi_variant: nil, skip_options: nil, skip_already_uploaded: nil)
            if profile
              return build_for_profile(profile, logger: logger, validate: validate)
            end

            loader = EmTools::Core::ProductFormatting::UploadedProductIds.from_env(logger: logger)
            uploaded =
              if loader
                loader.fetch(inventory_source)
              else
                Set.new
              end
            new(
              uploaded_product_ids: uploaded,
              logger: logger,
              validate: validate,
              display_source: display_source || "Lazada TH",
              sku_prefix: sku_prefix || "LZ-TH-",
              price_rules: price_rules,
              skip_multi_variant: skip_multi_variant.nil? ? true : skip_multi_variant,
              skip_options: skip_options.nil? ? true : skip_options,
              skip_already_uploaded: skip_already_uploaded.nil? ? true : skip_already_uploaded,
            )
          end

          def self.build_for_profile(profile, logger: nil, validate: true, inventory_source_override: nil)
            src = inventory_source_override.to_s.strip
            src = profile.inventory_source if src.empty?

            loader = EmTools::Core::ProductFormatting::UploadedProductIds.from_env(logger: logger)
            uploaded =
              if loader
                loader.fetch(src)
              else
                Set.new
              end
            new(
              uploaded_product_ids: uploaded,
              logger: logger,
              validate: validate,
              display_source: profile.display_source,
              sku_prefix: profile.sku_prefix,
              price_rules: profile.price_rules_hash,
              skip_multi_variant: profile.skip_multi_variant?,
              skip_options: profile.skip_options?,
              skip_already_uploaded: profile.skip_already_uploaded?,
            )
          end

          # @param source [Hash]
          # @return [Hash] export payload or {SKIP}
          def call(source)
            work = dup_source(source)
            return SKIP if @skip_multi_variant && skip_multi_variants?(work)
            return SKIP if @skip_options && options_present?(work)

            work["variants"] = nil

            return SKIP if @skip_already_uploaded && skip_already_uploaded?(work)

            standardize!(work)
            return SKIP unless validate_standard_product!(work)

            @price_formatter.call(work)
          end

          private

          def dup_source(source)
            JSON.parse(JSON.generate(source))
          end

          def skip_multi_variants?(work)
            variants = work["variants"]
            variants.is_a?(Array) && variants.size > 1
          end

          def options_present?(work)
            opts = work["options"]
            case opts
            when nil then false
            when Hash then !opts.empty?
            when Array then !opts.empty?
            else opts ? true : false
            end
          end

          def skip_already_uploaded?(work)
            pid = work["product_id"].to_s.strip
            !pid.empty? && @uploaded.include?(pid)
          end

          def standardize!(work)
            work["source"] = @display_source
            work["shipping_days_min"] = nil
            work["shipping_days_max"] = nil
            work["sku"] = "#{@sku_prefix}#{work["product_id"]}"

            desc = work["description"]
            if desc.to_s.strip.empty? && work["specifications"].is_a?(Array) && work["specifications"].any?
              work["description"] = EmTools::Core::ProductFormatting::DescriptionFormatter
                .generate_description_by_specifications(work["specifications"])
            end
            work
          end

          def validate_standard_product!(work)
            return true unless @validate

            EmProduct::StandardProduct.new(work)
            true
          rescue EmProduct::ValidationError, ArgumentError, KeyError => e
            @logger.warn { "Invalid product id=#{work["product_id"]}: #{e}" }
            false
          end

          def default_price_calculator(rules)
            EmTools::Plugins::Amazon::Uploadable::Transforms::PriceCalculator.new(
              price_rules: rules,
            )
          end
        end
      end
    end
  end
end
