# frozen_string_literal: true

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Transforms
          # Ruby port of +em_tasks/utils/price_calculator.py::PriceCalculator+. Converts a source
          # offer (raw price + currency) into a target-currency listing offer +{ price, quantity,
          # currency, src_price, src_currency }+ using the configured pricing rules and a target FX
          # rate from {EmTools::Clients::ExchangeRate}.
          #
          # Only the slice consumed by the ported formatter / pipeline is implemented:
          # +calc_offer+, +calc_cost_usd+, +calc_cost+, plus the +target_currency+ accessor.
          # +calc_profit+ and +calc_profit_rate+ from the Python class are not ported because no
          # caller in this gem references them today. # -- mirrors Python pricing surface; splitting blurs the formula.
          class PriceCalculator
            DEFAULT_RULES = {
              "roi" => 0.75,
              "ad_cost" => 3,
              "transfer_cost" => 0,
              "product_cost_rate" => 0.5,
              "margin" => 0.5,
              "tax_rate" => 0.09,
            }.freeze

            attr_reader :rules, :target_currency, :min_profit_amount, :default_qty, :exchange_rate

            # @param price_rules [Hash, nil] overrides for {DEFAULT_RULES}; symbol or string keys.
            # @param target_currency [String]
            # @param min_profit_amount [Numeric]
            # @param default_qty [Integer]
            # @param exchange_rate [Numeric, nil] precomputed +USD -> target_currency+ rate; when nil
            #   we look it up via +exchange_rate_provider+.
            # @param exchange_rate_provider [#call] callable receiving +(base, target)+ that returns
            #   a Numeric rate. Defaults to +EmTools::Clients::ExchangeRate.get_exchange_rate+. # -- mirrors Python constructor surface
            def initialize(price_rules: nil, target_currency: "USD", min_profit_amount: 10,
              default_qty: 50, exchange_rate: nil, exchange_rate_provider: nil)
              @rules = DEFAULT_RULES.dup
              apply_overrides!(price_rules) if price_rules

              @target_currency = target_currency.to_s.upcase
              @min_profit_amount = min_profit_amount
              @default_qty = default_qty
              @exchange_rate_provider = exchange_rate_provider || method(:default_exchange_rate_lookup)
              @exchange_rate = exchange_rate || @exchange_rate_provider.call("USD", @target_currency)
            end

            # Mirrors Python +calc_offer(src_offer)+:
            # - +false+ in -> +false+ out
            # - nil / zero price in -> zero offer with target currency
            # - otherwise compute target price by max(amount-floor, margin) and clamp by product-cost
            def calc_offer(src_offer)
              return false if src_offer == false
              return zero_offer if src_offer.nil? || (src_offer.respond_to?(:[]) && (src_offer["price"] || 0).to_f.zero?)

              src_currency = (src_offer["currency"] || "USD").to_s.upcase
              src_price_in_usd = src_offer["price"].to_f
              if src_currency != "USD"
                src_to_usd = @exchange_rate_provider.call("USD", src_currency)
                src_price_in_usd /= src_to_usd if src_to_usd
              end

              src_price = src_price_in_usd * @exchange_rate

              price_in_usd_amount = src_price_in_usd + @rules["transfer_cost"].to_f + @min_profit_amount.to_f
              price_in_usd_margin = (
                @rules["ad_cost"].to_f + @rules["transfer_cost"].to_f +
                  src_price_in_usd * (1 + @rules["tax_rate"].to_f)
              ) / (1 - @rules["margin"].to_f)
              price_in_usd = [price_in_usd_amount, price_in_usd_margin].max
              price_by_margin = price_in_usd * @exchange_rate

              cost = calc_cost(src_offer)
              price_by_product_cost = (
                cost / @rules["product_cost_rate"].to_f +
                  @rules["ad_cost"].to_f + @rules["transfer_cost"].to_f
              )
              price_by_product_cost = [price_in_usd_amount * @exchange_rate, price_by_product_cost].max

              price = [price_by_margin, price_by_product_cost].min

              {
                "price" => price.round(2),
                "quantity" => resolve_quantity(src_offer),
                "currency" => @target_currency,
                "src_price" => src_price,
                "src_currency" => @target_currency,
              }
            end
            # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

            # Returns the source price expressed in USD with tax applied, rounded to 2dp. Matches
            # Python +calc_cost_usd+: returns 0 for falsy / zero-price input.
            # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity -- mirrors Python branching
            def calc_cost_usd(src_offer)
              return 0 if src_offer.nil? || src_offer == false
              return 0 if (src_offer["price"] || 0).to_f.zero?

              src_currency = (src_offer["currency"] || "USD").to_s.upcase
              src_price_in_usd = src_offer["price"].to_f
              if src_currency != "USD"
                src_to_usd = @exchange_rate_provider.call("USD", src_currency)
                src_price_in_usd /= src_to_usd if src_to_usd
              end

              (src_price_in_usd * (1 + @rules["tax_rate"].to_f)).round(2)
            end
            # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

            # Cost in target currency.
            def calc_cost(src_offer)
              (calc_cost_usd(src_offer) * @exchange_rate).round(2)
            end

            private

            def apply_overrides!(price_rules)
              price_rules.each do |key, value|
                @rules[key.to_s] = value
              end
            end

            def default_exchange_rate_lookup(base, target)
              EmTools::Clients::ExchangeRate.get_exchange_rate(base, target)
            end

            def zero_offer
              {
                "price" => 0,
                "quantity" => 0,
                "currency" => @target_currency,
                "src_price" => 0,
                "src_currency" => @target_currency,
              }
            end

            def resolve_quantity(src_offer)
              src_quantity = src_offer["quantity"]
              return src_quantity if src_quantity

              shipping_time = src_offer["shipping_time"] || {}
              availability_type = shipping_time["availability_type"]
              fba = src_offer["fba"] == true
              if availability_type && !availability_type.to_s.downcase.include?("now") && !fba
                0
              else
                @default_qty
              end
            end
          end
        end
      end
    end
  end
end
