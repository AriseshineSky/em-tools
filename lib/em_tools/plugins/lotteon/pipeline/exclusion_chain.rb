# frozen_string_literal: true

module EmTools
  module Plugins
    module Lotteon
      module Pipeline
        # Composes several keyword / domain exclusion policies that share the same
        # duck interface as {EmTools::Core::Blacklist}-built strategies (+blocked?+,
        # optional +matched+, +blocked_record+, +keyword_count+).
        #
        # Evaluation is **short-circuit OR**: the first policy that reports +blocked?+
        # wins for +matched+ / +blocked_record+ so audit side-files stay meaningful.
        class ExclusionChain
          def initialize(policies)
            @policies = policies.compact.freeze
            raise ArgumentError, "ExclusionChain requires at least one policy" if @policies.empty?
          end

          def blocked?(source)
            @policies.any? { |p| p.blocked?(source) }
          end

          def matched(source)
            blocker = @policies.find { |p| p.blocked?(source) }
            return [] unless blocker

            blocker.respond_to?(:matched) ? Array(blocker.matched(source)) : ["blocked"]
          end

          def blocked_record(source, id:)
            blocker = @policies.find { |p| p.blocked?(source) }
            return fallback_blocked_record(source, id: id) unless blocker

            if blocker.respond_to?(:blocked_record)
              blocker.blocked_record(source, id: id)
            else
              fallback_blocked_record(source, id: id)
            end
          end

          def keyword_count
            @policies.sum { |p| p.respond_to?(:keyword_count) ? p.keyword_count.to_i : 0 }
          end

          private

          def fallback_blocked_record(source, id:)
            {
              "_id" => id,
              "title" => source["title"],
              "brand" => source["brand"],
              "matched" => matched(source),
            }
          end
        end
      end
    end
  end
end
