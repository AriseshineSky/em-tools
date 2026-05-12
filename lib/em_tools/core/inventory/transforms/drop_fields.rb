# frozen_string_literal: true

module EmTools
  module Core
    module Inventory
      module Transforms
        # Per-row transform that strips a fixed list of fields off every doc before it is
        # bulk-indexed. Handy for removing storefront-only payload (+handle+, +variants+)
        # from generic inventory feeds where those columns leak into the CSV.
        #
        # Implements the same +#call(doc) -> doc+ contract as plugin transforms
        # ({EmTools::Core::Plugin::Base#transforms}), so a future +PipelineEngine+
        # can pick it up without code changes.
        class DropFields
          # @param fields [Array<String, Symbol>] field names to strip. Compared after
          #   header normalization (i.e. snake_case as stored on the doc).
          def initialize(*fields)
            @fields = Array(fields).flatten.compact.map { |f| f.to_s.strip }.reject(&:empty?).freeze
          end

          # @param doc [Hash]
          # @return [Hash] the same +doc+ instance, mutated in place.
          def call(doc)
            return doc if @fields.empty?

            @fields.each { |f| doc.delete(f) }
            doc
          end

          # @return [Array<String>] frozen list of fields this transform removes.
          attr_reader :fields
        end
      end
    end
  end
end
