# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Registry of rule strategies under +EmTools::Core::Rules+. Mirrors em-tasks' Python +rules.registry+.
      # Rule classes are listed explicitly so they can be looked up by name without scanning the filesystem.
      module Registry
        RULE_CLASS_NAMES = %w[
          BatteryFilter
          CategoryIdFilter
          DimensionFilter
          FlammableFilter
          FoamFilter
          FoodFilter
          FreshFoodFilter
          HazmatFilter
          LighterFilter
          PaintFilter
          PaintHazmatFilter
          TempSensitiveFilter
          TitleKgKeywordFilter
        ].freeze

        class UnknownRuleError < StandardError; end

        class << self
          # Look up a rule class by case-insensitive simple class name (e.g. +"BatteryFilter"+ or +"batteryfilter"+).
          def lookup(name)
            target = name.to_s.downcase
            class_name = RULE_CLASS_NAMES.find { |n| n.downcase == target }
            unless class_name
              raise UnknownRuleError,
                    "Unknown rule: #{name}. Available: #{RULE_CLASS_NAMES.inspect}"
            end

            Rules.const_get(class_name)
          end

          def get(name, **opts)
            lookup(name).new(**opts)
          end

          def all(**opts)
            RULE_CLASS_NAMES.map { |class_name| Rules.const_get(class_name).new(**opts) }
          end

          def class_names
            RULE_CLASS_NAMES
          end
        end
      end
    end
  end
end
