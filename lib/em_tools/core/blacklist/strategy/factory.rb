# frozen_string_literal: true

module EmTools
  module Core
    module Blacklist
      module Strategy
        class Factory
          STRATEGIES = {
            "title_brand" => TitleBrand,
          }.freeze

          def self.build(rule, keywords:)
            strategy_name = rule.fetch("strategy")
            klass = STRATEGIES[strategy_name]
            unless klass
              raise EmTools::Core::Errors::ConfigurationError,
                "Unknown blacklist strategy: #{strategy_name.inspect}"
            end

            klass.new(keywords, **strategy_options(rule))
          end

          def self.strategy_options(rule)
            rule.fetch("options", {}).transform_keys(&:to_sym)
          end
          private_class_method :strategy_options
        end
      end
    end
  end
end
