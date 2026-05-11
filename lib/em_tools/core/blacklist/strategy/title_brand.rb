# frozen_string_literal: true

module EmTools
  module Core
    module Blacklist
      module Strategy
        # Source strategy for product-like documents: join title and brand, then run the text
        # through the configured blacklist engine. This is intentionally source-aware; other
        # sources can add their own strategy without changing the facade or downloader.
        class TitleBrand
          attr_reader :keyword_count

          def initialize(keywords, title_field: "title", brand_field: "brand", case_sensitive: false)
            @title_field = title_field.to_s
            @brand_field = brand_field.to_s
            @case_sensitive = case_sensitive
            @engine = Engine::AhoCorasick.new(keywords, case_sensitive: case_sensitive)
            @keyword_count = @engine.keyword_count
          end

          def allow?(source)
            !blocked?(source)
          end

          def blocked?(source)
            text = text_for(source)
            return false if text.empty?

            @engine.blocked?(text)
          end

          def matched(source)
            text = text_for(source)
            return [] if text.empty?

            @engine.lookup(text)
          end

          def text_for(source)
            return "" unless source.is_a?(Hash)

            [source[@title_field], source[@brand_field]]
              .compact
              .map(&:to_s)
              .reject(&:empty?)
              .join(" ")
              .then { |text| @case_sensitive ? text : text.downcase }
          end

          def blocked_record(source, id:)
            {
              "_id" => id,
              "title" => source[@title_field],
              "brand" => source[@brand_field],
              "matched" => matched(source),
            }
          end
        end
      end
    end
  end
end
