# frozen_string_literal: true

module EmTools
  module Core
    module Es
      # Pure-function vocabulary for the Elasticsearch query DSL.
      #
      # Every method returns a plain Hash that you can either pass into
      # +EmTools::Clients::ElasticsearchClient#iterate_query(query: ...)+ /
      # +#search(body: { query: ... })+ directly, or compose into bigger
      # clauses with {bool}.
      #
      # This module deliberately lives in +core+ (shared across plugins) and
      # is **stateless**. Anything that needs to know domain rules ("oliveyoung
      # filters by +source=oliveyoung+", "AMZ activity uses +time+ field")
      # belongs in a plugin-local +Queries::*+ class that *uses* these
      # primitives.
      #
      # == Examples
      #
      #   include EmTools::Core::Es::Query  # optional; methods are also +module_function+
      #
      #   # source filter
      #   Query.term(:source, "oliveyoung")
      #   # => { term: { source: "oliveyoung" } }
      #
      #   # full bool query — feed straight into +iterate_query(query: ...)+
      #   Query.bool(filter: [Query.term(:source, "oliveyoung")])
      #   # => { bool: { filter: [{ term: { source: "oliveyoung" } }] } }
      #
      #   # search-body envelope when you do need to call +client.search(body: ...)+
      #   { query: Query.bool(filter: [Query.term(:source, "oliveyoung")]) }
      #
      # == Design notes
      #
      # * Field arguments are passed through unchanged — pass +:source+ when you
      #   want a symbol key, +"source.keyword"+ when you need the keyword
      #   subfield. The module never rewrites field names.
      # * Returned Hashes are not frozen so callers can merge extra knobs
      #   (+_name+, +boost+, ...) without dup'ing first.
      module Query
        extend self

        # Match-all (the default when no query is supplied).
        #
        #   Query.match_all
        #   # => { match_all: {} }
        def match_all
          { match_all: {} }
        end

        # Single-value term filter.
        #
        #   Query.term(:source, "oliveyoung")
        #   # => { term: { source: "oliveyoung" } }
        def term(field, value)
          { term: { field => value } }
        end

        # Multi-value terms filter (use this instead of OR-ing many +term+ clauses).
        #
        #   Query.terms("asin.keyword", ["B0001", "B0002"])
        #   # => { terms: { "asin.keyword" => ["B0001", "B0002"] } }
        def terms(field, values)
          { terms: { field => Array(values) } }
        end

        # Range filter. +bounds+ is a Hash like +{ gte: "now-24h", lt: "now" }+.
        #
        #   Query.range(:time, gte: "now-24h", lt: "now")
        #   # => { range: { time: { gte: "now-24h", lt: "now" } } }
        def range(field, **bounds)
          { range: { field => bounds } }
        end

        # +exists+ filter (field is indexed and non-null on the doc).
        def exists(field)
          { exists: { field: field } }
        end

        # Compose a bool query. Any of +must+, +filter+, +must_not+, +should+
        # may be omitted; +nil+ and empty arrays are dropped so the resulting
        # Hash stays minimal.
        #
        #   Query.bool(filter: [Query.term(:source, "oliveyoung")])
        #   # => { bool: { filter: [{ term: { source: "oliveyoung" } }] } }
        def bool(must: nil, filter: nil, must_not: nil, should: nil, minimum_should_match: nil)
          inner = {}
          add_clause(inner, :must, must)
          add_clause(inner, :filter, filter)
          add_clause(inner, :must_not, must_not)
          add_clause(inner, :should, should)
          inner[:minimum_should_match] = minimum_should_match unless minimum_should_match.nil?
          { bool: inner }
        end

        # Hash-aware coercion: a single clause Hash should become +[hash]+, not
        # +Array(hash)+ (which would explode it into +[[k, v], ...]+).
        def add_clause(inner, key, value)
          return if value.nil?

          list = value.is_a?(Hash) ? [value] : Array(value)
          return if list.empty?

          inner[key] = list
        end
      end
    end
  end
end
