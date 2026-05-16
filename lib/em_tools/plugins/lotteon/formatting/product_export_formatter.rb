# frozen_string_literal: true

require "json"
require "set"
require "product_validator"

module EmTools
  module Plugins
    module Lotteon
      module Formatting
        # Ruby port of +em_tasks/contexts/product_formatting/format_lotteon.py+ (+process_pids+,
        # +standard_product+, +to_upload+), using {EmTools::Core::ProductFormatting::UploadedProductIds},
        # {EmTools::Core::ProductFormatting::PriceFormatter},
        # {EmTools::Core::ProductFormatting::DescriptionFormatter}, and
        # {EmTools::Plugins::Amazon::Uploadable::Transforms::PriceCalculator}.
        #
        # Use as +converter+ on {Exporters::ProductsExporter}: returns a Hash or {SKIP}.
        class ProductExportFormatter
          SKIP = :skip

          # Matches +em_tasks/.../constants.py+ +DEFAULT_PRICE_RULES+.
          DEFAULT_PRICE_RULES = {
            "roi" => 0.3,
            "ad_cost" => 4.5,
            "transfer_cost" => 10,
          }.freeze

          TITLE_PROMO_FRAGMENTS = [": 롯데ON"].freeze

          # @param uploaded_product_ids [Set<String>]
          # @param price_calculator [#calc_offer]
          # @param price_formatter [EmTools::Core::ProductFormatting::PriceFormatter, nil]
          # @param logger [::Logger, nil]
          # @param validate [Boolean]
          def initialize(uploaded_product_ids:, price_calculator: nil, price_formatter: nil,
            logger: nil, validate: true)
            @uploaded = uploaded_product_ids
            @logger = logger || EmTools::Core::Logger.for(progname: "lotteon-product-export")
            @validate = validate
            @calc = price_calculator || default_price_calculator
            @price_formatter = price_formatter || EmTools::Core::ProductFormatting::PriceFormatter.new(
              price_calculator: @calc,
            )
          end

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

          def call(source)
            work = dup_source(source)
            return SKIP if skip_variants_or_options?(work)
            return SKIP if skip_already_uploaded?(work)

            std = standardize!(work)
            return SKIP if std.nil?

            return SKIP unless validate_standard_product!(std)

            @price_formatter.call(std)
          end

          private

          def dup_source(source)
            JSON.parse(JSON.generate(source))
          end

          def skip_variants_or_options?(work)
            v = work["variants"]
            return true if v.is_a?(Array) && !v.empty?
            return true if v.is_a?(Hash) && !v.empty?

            o = work["options"]
            return true if o.is_a?(Array) && !o.empty?
            return true if o.is_a?(Hash) && !o.empty?

            false
          end

          def skip_already_uploaded?(work)
            pid = work["product_id"].to_s.strip
            !pid.empty? && @uploaded.include?(pid)
          end

          def standardize!(work)
            raw_title = work["title"].to_s.strip
            return if raw_title.empty?

            work["title"] = clean_title(raw_title)
            work["source"] = "lotteon"
            work["existence"] = true
            work["shipping_days_min"] = nil
            work["shipping_days_max"] = nil
            work["has_only_default_variant"] = true
            work["sku"] = "X91_#{work["product_id"]}"

            desc = work["description"]
            if desc
              once = EmTools::Core::ProductFormatting::DescriptionFormatter.remove_a_tag(desc)
              work["description"] = EmTools::Core::ProductFormatting::DescriptionFormatter.remove_a_tag(once)
            end

            work["specifications"] = remove_invalid_specifications(work["specifications"])
            work
          end

          def remove_invalid_specifications(specifications)
            return unless specifications.is_a?(Array)

            specs = specifications.select do |spec|
              spec.is_a?(Hash) && !["無し", "-"].include?(spec["value"].to_s.strip)
            end
            specs.empty? ? nil : specs
          end

          def clean_title(title)
            t = TITLE_PROMO_FRAGMENTS.inject(title.dup) { |acc, frag| acc.gsub(frag, "") }
            t = t.gsub(/[｜|]/, "-")
            t = t.gsub(/[-\s]+/, "-")
            t = t.sub(/\A-+/, "").sub(/-+\z/, "")
            t
          end

          def validate_standard_product!(work)
            return true unless @validate

            EmProduct::StandardProduct.new(work)
            true
          rescue EmProduct::ValidationError, ArgumentError, KeyError => e
            @logger.warn { "Invalid Lotteon product id=#{work["product_id"]}: #{e}" }
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
