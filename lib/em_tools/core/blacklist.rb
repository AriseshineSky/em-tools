# frozen_string_literal: true

module EmTools
  module Core
    # Stable facade for blacklist decisions.
    #
    # External callers should prefer this module over instantiating concrete checker/filter
    # classes. Internally, source-specific behavior is selected from
    # +config/blacklist/source_rules.yml+ and implemented by strategy objects.
    module Blacklist
      DEFAULT_RULE_SOURCE = "product_download"

      class << self
        def build(keywords:, rules_source: DEFAULT_RULE_SOURCE, rules_path: nil, overrides: {})
          rules = Rules::SourceRules.load(path: rules_path).fetch(rules_source)
          Strategy::Factory.build(merge_rules(rules, overrides), keywords: keywords)
        end

        def allow?(source, keywords:, rules_source: DEFAULT_RULE_SOURCE, rules_path: nil, overrides: {})
          build(
            keywords: keywords,
            rules_source: rules_source,
            rules_path: rules_path,
            overrides: overrides,
          ).allow?(source)
        end

        def blocked?(source, keywords:, rules_source: DEFAULT_RULE_SOURCE, rules_path: nil, overrides: {})
          !allow?(
            source,
            keywords: keywords,
            rules_source: rules_source,
            rules_path: rules_path,
            overrides: overrides,
          )
        end

        def matched(source, keywords:, rules_source: DEFAULT_RULE_SOURCE, rules_path: nil, overrides: {})
          build(
            keywords: keywords,
            rules_source: rules_source,
            rules_path: rules_path,
            overrides: overrides,
          ).matched(source)
        end

        private

        def merge_rules(rules, overrides)
          rules.merge(overrides) do |key, old_value, new_value|
            key == "options" ? old_value.merge(new_value) : new_value
          end
        end
      end
    end
  end
end
