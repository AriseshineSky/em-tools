# frozen_string_literal: true

require "json"
require "set"
require "product_validator"

module EmTools
  module Plugins
    module Oliveyoung
      module Formatting
        # Turns an Oliveyoung **product** document from Elasticsearch into the
        # **export** payload expected for downstream upload (same pipeline as
        # +em_tasks/contexts/product_formatting/format_oliveyoung.py+:
        # +process_pids+, +standard_product+, +to_upload+), reusing
        # {EmTools::Core::ProductFormatting::UploadedProductIds},
        # {EmTools::Core::ProductFormatting::PriceFormatter},
        # {EmTools::Core::ProductFormatting::DescriptionFormatter}, and
        # {EmTools::Plugins::Amazon::Uploadable::Transforms::PriceCalculator}.
        #
        # Use as the +converter+ for {Exporters::ProductsExporter}: returns a
        # Hash to JSON-serialize, or {SKIP} to drop the row (mirrors Python +continue+).
        class ProductExportFormatter
          SKIP = :skip

          # Default +PRICE_RULES+ from +format_oliveyoung.py+.
          DEFAULT_PRICE_RULES = {
            "roi" => 0.3,
            "ad_cost" => 4.5,
            "transfer_cost" => 0,
          }.freeze

          # @param uploaded_product_ids [Set<String>] Spree inventory
          #   +SourceProductID+ values already on the storefront (skip those rows).
          # @param price_calculator [#calc_offer] defaults to Oliveyoung rules.
          # @param price_formatter [EmTools::Core::ProductFormatting::PriceFormatter, nil]
          # @param logger [::Logger, nil]
          # @param validate [Boolean] when true, run {EmProduct::StandardProduct} like Python.
          def initialize(uploaded_product_ids:, price_calculator: nil, price_formatter: nil,
            logger: nil, validate: true)
            @uploaded = uploaded_product_ids
            @logger = logger || EmTools::Core::Logger.for(progname: "oliveyoung-product-export")
            @validate = validate
            @calc = price_calculator || default_price_calculator
            @price_formatter = price_formatter || EmTools::Core::ProductFormatting::PriceFormatter.new(
              price_calculator: @calc,
            )
          end

          # @param inventory_source [String] Spree inventory CSV source code (e.g. +"oliveyoung"+).
          # @return [ProductExportFormatter]
          def self.build(inventory_source:, logger: nil, validate: true)
            loader = EmTools::Core::ProductFormatting::UploadedProductIds.from_env(logger: logger)
            uploaded =
              if loader
                loader.fetch(inventory_source)
              else
                Set.new
              end
            new(uploaded_product_ids: uploaded, logger: logger, validate: validate)
          end

          # @param source [Hash] ES +_source+ document (string keys).
          # @return [Hash] mutated export payload, or {SKIP} when the row should not be written.
          def call(source)
            work = dup_source(source)
            return SKIP if skip_multi_variants?(work)
            return SKIP if options_present?(work)

            work["variants"] = nil

            return SKIP if skip_already_uploaded?(work)

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
            work["source"] = "Oliveyoung"
            work["shipping_days_min"] = nil
            work["shipping_days_max"] = nil
            work["sku"] = "X92-#{work["product_id"]}"

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

          def default_price_calculator
            EmTools::Plugins::Amazon::Uploadable::Transforms::PriceCalculator.new(
              price_rules: DEFAULT_PRICE_RULES,
            )
          end
        end
      end
    end
  end
end
