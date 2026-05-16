# frozen_string_literal: true

module EmTools
  module Core
    module ProductFormatting
      # Ruby port of +em_tasks/contexts/product_formatting/price_formatter.py::to_upload+.
      #
      # Walks a product hash (and its variants), runs every leaf offer through a
      # +PriceCalculator+, and writes the calculated +price+ / +quantity+ /
      # +cost_price+ / +currency+ / +cost_currency+ back onto the hash. Variants
      # whose calculated quantity is non-positive are dropped (the parent is
      # zeroed in place but never removed).
      #
      # Mutates the supplied hash in place and returns it (matches the Python
      # contract; downstream callers serialize the same object).
      #
      # The +PriceCalculator+ collaborator must respond to +#calc_offer(src_offer)+
      # and return either +false+ (skip / fall back to zero) or a hash with
      # +"price"+, +"quantity"+, +"src_price"+, +"src_currency"+, +"currency"+
      # keys. {EmTools::Plugins::Amazon::Uploadable::Transforms::PriceCalculator}
      # is the canonical implementation, but anything matching the contract
      # works (e.g. a stub in tests, a different marketplace's calculator).
      class PriceFormatter
        # @param price_calculator [#calc_offer]
        def initialize(price_calculator:)
          @price_calculator = price_calculator
        end

        # @param product [Hash] mutated in place; the same object is returned.
        # @return [Hash]
        def call(product)
          apply_parent_offer!(product)
          rebuild_variants!(product)
          product
        end

        private

        # Parent: any non-+false+ offer is accepted (incl. zero-price); only a
        # +false+ return triggers the zero-out branch. Mirrors Python +if offer:+.
        def apply_parent_offer!(product)
          src_offer = build_src_offer(product)
          offer = @price_calculator.calc_offer(src_offer)
          if offer
            copy_offer!(product, offer)
          else
            zero_out!(product, fallback_currency: src_offer["currency"])
          end
        end

        # Variant: requires a positive price as well (a zero-priced variant
        # cannot be listed). Mirrors Python +if offer and offer["price"]:+ — but
        # in Ruby +0+ is truthy, so we compare explicitly.
        def apply_variant_offer!(variant)
          src_offer = build_src_offer(variant)
          offer = @price_calculator.calc_offer(src_offer)
          if offer && (offer["price"] || 0).to_f.positive?
            copy_offer!(variant, offer)
          else
            zero_out!(variant, fallback_currency: src_offer["currency"])
          end
        end

        def rebuild_variants!(product)
          variants = product["variants"]
          return if variants.nil? || variants.empty?

          product["variants"] = variants.each_with_object([]) do |variant, acc|
            apply_variant_offer!(variant)
            acc << variant if variant["quantity"].to_i.positive?
          end
        end

        def build_src_offer(record)
          {
            "price" => (record["price"] || 0).to_f.round(2),
            "currency" => record["currency"] || "USD",
          }
        end

        def copy_offer!(record, offer)
          record["price"] = offer["price"].to_f.round(2)
          record["quantity"] = offer["quantity"]
          record["cost_price"] = offer["src_price"].to_f.round(2)
          record["cost_currency"] = offer["src_currency"]
          record["currency"] = offer["currency"]
        end

        def zero_out!(record, fallback_currency:)
          record["price"] = 0
          record["quantity"] = 0
          record["currency"] = fallback_currency
        end
      end
    end
  end
end
