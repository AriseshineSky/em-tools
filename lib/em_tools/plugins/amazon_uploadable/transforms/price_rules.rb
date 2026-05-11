# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonUploadable
      module Transforms
        # +cfg.get("price.rules.amz_{marketplace}", dict())+ merge behaviour.
        class PriceRules
          DEFAULTS = {
            roi: 0.3,
            ad_cost: 4.5,
            transfer_cost: 0.0,
          }.freeze

          attr_reader :values

          def initialize(values)
            @values = DEFAULTS.merge(values).freeze
          end

          def to_h
            @values.to_h
          end

          class << self
            def from_config(config, marketplace:)
              mp_code = marketplace.to_s.downcase.strip
              raw = extract_raw(config, mp_code)
              merged = DEFAULTS.dup
              return new(merged) unless raw.is_a?(Hash)

              raw.each do |rule_key, raw_val|
                key = rule_key.to_s
                merged[key.to_sym] = coerce_float(key, raw_val, merged[key.to_sym])
              end
              new(merged)
            end

            private

            def extract_raw(config, mp_code)
              return {} unless config.is_a?(Hash)

              flat = config["price.rules.amz_#{mp_code}"]
              return flat if flat.is_a?(Hash)

              rules = config.dig("price", "rules")
              return {} unless rules.is_a?(Hash)

              rules["amz_#{mp_code}"] || rules[:"amz_#{mp_code}"]
            end

            def coerce_float(key, value, fallback)
              Float(value).round(2)
            rescue ArgumentError, TypeError
              warn("em-tools: invalid price rule #{key.inspect}=#{value.inspect} (keeping #{fallback.inspect})")
              fallback
            end
          end
        end
      end
    end
  end
end
