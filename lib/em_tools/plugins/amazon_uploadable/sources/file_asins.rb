# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonUploadable
      module Sources
        # Streams ASIN seeds from a local text file, one ASIN per line.
        class FileAsins
          include EmTools::Core::Ports::AsinSource

          def initialize(path:, max_asins: nil)
            @path = File.expand_path(path.to_s)
            @max_asins = positive_integer(max_asins)
          end

          def each
            return enum_for(:each) unless block_given?

            count = 0
            File.foreach(@path, encoding: "utf-8") do |line|
              asin = normalize(line)
              next unless valid_asin?(asin)

              yield asin
              count += 1
              break if @max_asins && count >= @max_asins
            end
          end

          def describe
            { kind: "file", path: @path, max_asins: @max_asins }
          end

          private

          def normalize(value)
            value.to_s.strip.upcase
          end

          def valid_asin?(asin)
            EmTools::Plugins::AmazonLowestOffer::Patterns::AsinPattern.match?(asin)
          end

          def positive_integer(value)
            int = value&.to_i
            int&.positive? ? int : nil
          end
        end
      end
    end
  end
end
