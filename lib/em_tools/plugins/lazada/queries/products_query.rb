# frozen_string_literal: true

module EmTools
  module Plugins
    module Lazada
      module Queries
        # Elasticsearch query for Lazada product exports (per-marketplace index; optional
        # +source+ term and optional extra bool filters from YAML).
        class ProductsQuery
          DEFAULT_SOURCE_FIELD = :source

          # @param source_value [String, nil] when present, bool +term+ filter on +source_field+
          # @param source_field [Symbol, String]
          # @param extra_filters [Array<Hash>]
          def initialize(source_value: nil, source_field: DEFAULT_SOURCE_FIELD, extra_filters: [])
            @source_value = source_value
            @source_field = source_field
            @extra_filters = Array(extra_filters)
          end

          # @return [Hash] query body (no outer +query:+ key) for +iterate_query+
          def to_h
            sv = @source_value.to_s.strip
            if sv.empty? && @extra_filters.empty?
              EmTools::Core::Es::Query.match_all
            elsif sv.empty?
              EmTools::Core::Es::Query.bool(filter: @extra_filters)
            else
              filters = [EmTools::Core::Es::Query.term(@source_field, sv), *@extra_filters]
              EmTools::Core::Es::Query.bool(filter: filters)
            end
          end
        end
      end
    end
  end
end
