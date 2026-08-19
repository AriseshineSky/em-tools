# frozen_string_literal: true

require "yaml"

module EmTools
  module Plugins
    module Lotteon
      # Korean marketplace - Lotteon. Produces NDJSON exports against the secondary
      # ("data" / "analytics") Elasticsearch cluster, configured via the +exporters.lotteon_products+
      # block in settings YAML.
      #
      # == Upload payload pipeline
      #
      # +products build-upload-payload+ wires {Formatting::ProductExportFormatter} into
      # {Exporters::ProductsExporter} (+upload_payload: true+). The formatter mirrors
      # +em_tasks/contexts/product_formatting/format_lotteon.py+ (title cleanup, HTML
      # stripping, +StandardProduct+ check, Spree dedupe, +PriceFormatter+).
      #
      # == Composable exclusions / transforms
      #
      # Pass +exclusions:+ / +transforms:+ as arrays of policy-like (+#blocked?+) or
      # +#call(source)+ steps, and/or a +pipeline:+ Hash (or YAML path via the CLI
      # +--pipeline+) using {Pipeline::Registry} entry types. Multiple exclusions are
      # composed with {Pipeline::ExclusionChain}; multiple transforms with
      # {Pipeline::TransformChain}. An explicit +converter:+ still wins and bypasses
      # composed transforms.
      #
      # **Transform order (先格式化再精修):** (1) YAML +format+ entries, (2) any
      # +type: lotteon_upload_format+ rows from legacy +transforms:+, (3) the default
      # {Formatting::ProductExportFormatter} when +upload_payload+ and nothing else
      # supplied format steps, (4) all other legacy +transforms:+ rows, (5) YAML
      # +refine+ entries, (6) Ruby +transforms:+ keyword objects — all run after the
      # format stage in that order.
      class Plugin < EmTools::Core::Plugin::Base
        def self.plugin_name = :lotteon

        EmTools::Core::PluginRegistry.register(plugin_name, self)

        def capabilities
          {
            products: {
              exporter: Exporters::ProductsExporter,
            },
          }
        end

        def dependencies
          @dependencies ||= {
            es_client: EmTools::Clients::ElasticsearchClient.new(
              url: EmTools::Core::Config.exporter_elasticsearch_url(Exporters::ProductsExporter::EXPORTER_KEY),
            ),
          }
        end

        def cli_commands
          {
            "products export" => Cli::ExportProducts,
            "products build-upload-payload" => Cli::BuildUploadPayload,
          }
        end

        # @param client [EmTools::Clients::ElasticsearchClient]
        # @param apply_keyword_policy [Boolean]
        # @param keywords [Array<String>, nil]
        # @param blocked_output_path [String, nil]
        # @param title_field [String] keyword policy field
        # @param brand_field [String]
        # @param upload_payload [Boolean] wire {Formatting::ProductExportFormatter}
        # @param inventory_source [String] Spree inventory source for uploaded-ID skip
        # @param validate_payload [Boolean] run {EmProduct::StandardProduct}
        # @param converter [#call, nil] explicit converter overrides composed transforms
        # @param exclusions [Array<#blocked?>, nil] extra exclusion policies (OR keyword policy)
        # @param transforms [Array<#call>, nil] extra transform steps before/after defaults
        # @param pipeline [Hash, nil] optional +{"exclusions" => [...], "transforms" => [...]}+
        #   merged ahead of +pipeline_config+ file contents
        # @param pipeline_config [String, nil] path to YAML with +exclusions+ / +transforms+ lists
        # @param logger [::Logger, nil]
        # @param translation_index [String, nil] sidecar ES index for +title_en+ (see {Translation::TitleEnFromTranslationIndex})
        # @param translation_elasticsearch_url [String, nil] optional URL for translation cluster
        # @param translation_source_field [String]
        # @param translation_source_product_id_field [String]
        def products_exporter(client: dependencies[:es_client],
          apply_keyword_policy: false, keywords: nil, blocked_output_path: nil,
          title_field: "title", brand_field: "brand",
          upload_payload: false, inventory_source: "lotteon",
          validate_payload: true, converter: nil, logger: nil,
          exclusions: nil, transforms: nil, pipeline: nil, pipeline_config: nil,
          translation_index: nil, translation_elasticsearch_url: nil,
          translation_source_field: "source", translation_source_product_id_field: "source_product_id",
          **_opts)
          yaml = merge_pipeline_sources(pipeline, pipeline_config)

          exclusion_list = compose_exclusions(
            apply_keyword_policy: apply_keyword_policy,
            keywords: keywords,
            title_field: title_field,
            brand_field: brand_field,
            explicit: exclusions,
            yaml: yaml,
          )
          policy = wrap_exclusion_list(exclusion_list)

          resolved_converter = compose_converter(
            converter: converter,
            upload_payload: upload_payload,
            inventory_source: inventory_source,
            validate_payload: validate_payload,
            logger: logger,
            explicit_transforms: transforms,
            yaml: yaml,
          )

          resolved_converter = EmTools::Core::Translation::TitleEnFromTranslationIndex.compose_with(
            inner: resolved_converter,
            product_es_client: client,
            translation_index: translation_index,
            translation_elasticsearch_url: translation_elasticsearch_url,
            translation_source_field: translation_source_field,
            translation_source_product_id_field: translation_source_product_id_field,
          )

          capabilities.dig(:products, :exporter).new(
            client: client,
            policy: policy,
            blocked_output_path: policy ? blocked_output_path : nil,
            converter: resolved_converter,
            logger: logger,
          )
        end

        private

        def yaml_declares_keyword_blacklist?(yaml)
          return false unless yaml.is_a?(Hash)

          Array(yaml["exclusions"]).any? { |e| pipeline_entry_type(e) == "keyword_blacklist" }
        end

        def pipeline_entry_type(entry)
          return "" unless entry.is_a?(Hash)

          (entry["type"] || entry[:type]).to_s
        end

        def merge_pipeline_sources(pipeline, pipeline_config)
          h = {}
          h.merge!(pipeline) if pipeline.is_a?(Hash)
          if pipeline_config && !pipeline_config.to_s.strip.empty?
            path = File.expand_path(pipeline_config.to_s)
            unless File.file?(path)
              raise EmTools::Core::Errors::ConfigurationError, "pipeline config not found: #{path}"
            end

            loaded = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: true)
            unless loaded.is_a?(Hash)
              raise EmTools::Core::Errors::ConfigurationError, "pipeline YAML must be a mapping at top level"
            end

            h = h.merge(loaded)
          end
          h
        end

        def compose_exclusions(apply_keyword_policy:, keywords:, title_field:, brand_field:,
          explicit:, yaml:)
          list = []
          list.concat(Array(explicit))
          yaml_exclusions = yaml["exclusions"] if yaml.is_a?(Hash)
          if yaml_exclusions
            factory = ->(entry) { build_keyword_policy_from_pipeline_entry(entry, keywords: keywords, title_field: title_field, brand_field: brand_field) }
            list.concat(Pipeline::Registry.build_exclusions(yaml_exclusions, keyword_policy_factory: factory))
          end
          if apply_keyword_policy && !yaml_declares_keyword_blacklist?(yaml)
            list.unshift(build_keyword_policy(keywords: keywords, title_field: title_field, brand_field: brand_field))
          end
          list.compact
        end

        def wrap_exclusion_list(list)
          return if list.empty?
          return list.first if list.size == 1

          Pipeline::ExclusionChain.new(list)
        end

        def compose_converter(converter:, upload_payload:, inventory_source:, validate_payload:,
          logger:, explicit_transforms:, yaml:)
          return converter if converter

          yaml = {} unless yaml.is_a?(Hash)

          format_steps = []
          refine_steps = []

          format_steps.concat(
            build_transform_step_list(
              yaml["format"],
              logger: logger,
              inventory_source: inventory_source,
              validate_payload: validate_payload,
            ),
          )

          if yaml["transforms"]
            fmt_entries, ref_entries = partition_transform_pipeline_entries(yaml["transforms"])
            format_steps.concat(
              build_transform_step_list(
                fmt_entries,
                logger: logger,
                inventory_source: inventory_source,
                validate_payload: validate_payload,
              ),
            )
            refine_steps.concat(
              build_transform_step_list(
                ref_entries,
                logger: logger,
                inventory_source: inventory_source,
                validate_payload: validate_payload,
              ),
            )
          end

          refine_steps.concat(
            build_transform_step_list(
              yaml["refine"],
              logger: logger,
              inventory_source: inventory_source,
              validate_payload: validate_payload,
            ),
          )

          refine_steps.concat(Array(explicit_transforms))

          if format_steps.empty? && upload_payload
            format_steps << Formatting::ProductExportFormatter.build(
              inventory_source: inventory_source,
              logger: logger,
              validate: validate_payload,
            )
          end

          steps = format_steps + refine_steps
          return if steps.empty?
          return steps.first if steps.size == 1

          Pipeline::TransformChain.new(steps)
        end

        def build_transform_step_list(entries, logger:, inventory_source:, validate_payload:)
          return [] if entries.nil? || Array(entries).empty?

          Pipeline::Registry.build_transforms(
            entries,
            logger: logger,
            default_inventory_source: inventory_source,
            default_validate: validate_payload,
          )
        end

        def partition_transform_pipeline_entries(entries)
          format_entries = []
          refine_entries = []
          Array(entries).each do |e|
            if pipeline_entry_type(e) == "lotteon_upload_format"
              format_entries << e
            else
              refine_entries << e
            end
          end
          [format_entries, refine_entries]
        end

        def build_keyword_policy_from_pipeline_entry(entry, keywords:, title_field:, brand_field:)
          h =
            if entry.is_a?(Hash)
              entry.transform_keys { |k| k.is_a?(String) ? k.to_sym : k }
            else
              {}
            end
          build_keyword_policy(
            keywords: keywords,
            title_field: (h[:title_field] || title_field).to_s,
            brand_field: (h[:brand_field] || brand_field).to_s,
          )
        end

        def build_keyword_policy(keywords:, title_field:, brand_field:)
          words = (keywords && Array(keywords)) || EmTools::Core::Blacklist::Loader.new.fetch_keywords
          EmTools::Core::Blacklist.build(
            keywords: words,
            rules_source: "product_download",
            overrides: {
              "options" => {
                "title_field" => title_field,
                "brand_field" => brand_field,
              },
            },
          )
        end
      end
    end
  end
end
