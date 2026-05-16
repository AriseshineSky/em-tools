# frozen_string_literal: true

require "digest"

module EmTools
  module Core
    module Translation
      # Deterministic Elasticsearch document id for a (source, source_product_id) pair.
      # Uses SHA256 so arbitrary characters in +source_product_id+ stay within ES _id rules.
      module DocId
        extend self

        # @param source [String] marketplace / feed source key (e.g. +"oliveyoung"+)
        # @param source_product_id [String] stable product id in that source
        # @return [String] hex digest, safe as ES +_id+
        def encode(source, source_product_id)
          s = source.to_s.strip
          p = source_product_id.to_s.strip
          Digest::SHA256.hexdigest("#{s}\u{0}#{p}")
        end
      end
    end
  end
end
