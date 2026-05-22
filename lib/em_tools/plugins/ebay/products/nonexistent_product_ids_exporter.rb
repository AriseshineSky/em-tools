# frozen_string_literal: true

module EmTools
  module Plugins
    module Ebay
      module Products
        # Exports +product_id+ values where +existence+ is false.
        class NonexistentProductIdsExporter
          DEFAULT_INDEX = ProductIdsExporter::DEFAULT_INDEX
          DEFAULT_ID_FIELD = ProductIdsExporter::DEFAULT_ID_FIELD

          def initialize(es_client:, index: DEFAULT_INDEX, id_field: DEFAULT_ID_FIELD, logger: nil)
            @delegate = ProductIdsExporter.new(
              es_client: es_client,
              index: index,
              id_field: id_field,
              query: self.class.build_query,
              source_filter: self.class.source_filter,
              logger: logger,
            )
          end

          def export!(output_path)
            @delegate.export!(output_path)
          end

          def self.build_query
            { term: { existence: false } }
          end

          def self.source_filter
            lambda do |source|
              return false unless source.is_a?(Hash)

              value = boolean_field(source, "existence")
              value == false || value.to_s.strip.casecmp?("false")
            end
          end

          def self.boolean_field(source, name)
            return source[name] if source.key?(name)

            sym = name.to_sym
            source[sym] if source.key?(sym)
          end
          private_class_method :boolean_field
        end
      end
    end
  end
end
