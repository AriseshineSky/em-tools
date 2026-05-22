# frozen_string_literal: true

module EmTools
  module Plugins
    module Ebay
      module Products
        # Exports +product_id+ values where +redirect+ is true and +redirect_url+ contains +/p/+.
        class RedirectProductIdsExporter
          DEFAULT_INDEX = ProductIdsExporter::DEFAULT_INDEX
          DEFAULT_ID_FIELD = ProductIdsExporter::DEFAULT_ID_FIELD
          REDIRECT_URL_SUBSTRING = "/p/"

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
            # Filter +redirect_url+ for +/p/+ in Ruby; wildcard on +redirect_url+ is unreliable on text fields.
            { term: { redirect: true } }
          end

          def self.source_filter
            substring = REDIRECT_URL_SUBSTRING
            lambda do |source|
              return false unless source.is_a?(Hash)

              redirect = source["redirect"] || source[:redirect]
              return false unless redirect == true || redirect.to_s.strip.casecmp?("true")

              url = (source["redirect_url"] || source[:redirect_url]).to_s
              url.include?(substring)
            end
          end
        end
      end
    end
  end
end
