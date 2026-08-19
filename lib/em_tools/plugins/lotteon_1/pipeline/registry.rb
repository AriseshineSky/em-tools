# frozen_string_literal: true

module EmTools
  module Plugins
    module Lotteon
      module Pipeline
        # YAML-driven construction of exclusion policies and upload transforms.
        #
        # Each list entry is a Hash with string keys +{"type" => "...", ...}+.
        # Unknown +type+ raises {EmTools::Core::Errors::ConfigurationError}.
        module Registry
          class << self
            def build_exclusions(entries, keyword_policy_factory:)
              Array(entries).map { |entry| build_one_exclusion(entry, keyword_policy_factory: keyword_policy_factory) }
            end

            def build_transforms(entries, logger:, default_inventory_source:, default_validate:)
              Array(entries).map do |entry|
                build_one_transform(
                  entry,
                  logger: logger,
                  default_inventory_source: default_inventory_source,
                  default_validate: default_validate,
                )
              end
            end

            def build_one_exclusion(entry, keyword_policy_factory:)
              hash = symbolize_shallow(entry)
              case (hash[:type] || hash["type"]).to_s
              when "keyword_blacklist"
                keyword_policy_factory.call(entry)
              when "min_title_length"
                min = Integer(hash[:min] || 1)
                title_field = (hash[:title_field] || "title").to_s
                Exclusions::MinTitleLength.new(min: min, title_field: title_field)
              else
                raise EmTools::Core::Errors::ConfigurationError,
                  "unknown Lotteon pipeline exclusion type: #{hash[:type] || hash["type"]}"
              end
            end

            def build_one_transform(entry, logger:, default_inventory_source:, default_validate:)
              hash = symbolize_shallow(entry)
              case (hash[:type] || hash["type"]).to_s
              when "lotteon_upload_format"
                inventory = (hash[:inventory_source] || hash["inventory_source"] || default_inventory_source).to_s
                v = hash[:validate]
                validate = v.nil? ? default_validate : truthy?(v)
                Formatting::ProductExportFormatter.build(
                  inventory_source: inventory,
                  logger: logger,
                  validate: validate,
                )
              else
                raise EmTools::Core::Errors::ConfigurationError,
                  "unknown Lotteon pipeline transform type: #{hash[:type] || hash["type"]}"
              end
            end

            private

            def symbolize_shallow(entry)
              raise EmTools::Core::Errors::ConfigurationError, "pipeline entry must be a Hash" unless entry.is_a?(Hash)

              entry.transform_keys { |k| k.is_a?(String) ? k.to_sym : k }
            end

            def truthy?(value)
              case value
              when true, false then value
              when String then !["0", "false", "no", "off"].include?(value.downcase)
              when Integer then !value.zero?
              when nil then false
              else
                !!value
              end
            end
          end
        end
      end
    end
  end
end
