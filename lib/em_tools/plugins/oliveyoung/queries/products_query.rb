# frozen_string_literal: true

module EmTools
  module Plugins
    module Oliveyoung
      module Queries
        # Domain query for the Oliveyoung products exporter.
        #
        # The exporter pulls from a shared product index that mixes multiple
        # marketplaces; this class owns the rules that say "from that index,
        # what counts as an Oliveyoung product?". Today that's a single
        # +source+ term filter. Tomorrow it can grow to include status,
        # availability windows, etc. — all without leaking those rules into
        # the exporter.
        #
        # Built on top of {EmTools::Core::Es::Query} primitives so the actual
        # ES DSL stays in one place.
        #
        # == Example
        #
        #   query = EmTools::Plugins::Oliveyoung::Queries::ProductsQuery.new
        #   query.to_h
        #   # => { bool: { filter: [{ term: { source: "oliveyoung" } }] } }
        #
        #   # feed directly into iterate_query
        #   es_client.iterate_query(index: "oliveyoung_products", query: query.to_h) { |hit| ... }
        class ProductsQuery
          DEFAULT_SOURCE_VALUE = "oliveyoung"
          DEFAULT_SOURCE_FIELD = :source

          # @param source_value [String] the +source+ field value identifying
          #   Oliveyoung-origin docs. Override per-call (or via env in the
          #   plugin factory) if your index uses a different casing/code.
          # @param source_field [Symbol, String] the field name to match
          #   against; defaults to +:source+. Pass +"source.keyword"+ if your
          #   mapping requires the keyword subfield.
          # @param extra_filters [Array<Hash>] additional bool-filter clauses
          #   (built with {EmTools::Core::Es::Query}) merged into the same
          #   +bool.filter+ array.
          def initialize(source_value: DEFAULT_SOURCE_VALUE, source_field: DEFAULT_SOURCE_FIELD, extra_filters: [])
            @source_value = source_value
            @source_field = source_field
            @extra_filters = Array(extra_filters)
          end

          # @return [Hash] the query value (no top-level +query:+ envelope).
          def to_h
            EmTools::Core::Es::Query.bool(filter: filters)
          end

          private

          def filters
            [EmTools::Core::Es::Query.term(@source_field, @source_value), *@extra_filters]
          end
        end
      end
    end
  end
end
