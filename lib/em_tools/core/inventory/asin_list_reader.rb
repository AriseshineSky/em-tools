# frozen_string_literal: true

module EmTools
  module Core
    module Inventory
      # Reads one ASIN (or product id) per line; skips blanks and +#+ comments.
      module AsinListReader
        module_function

        # @param path [String]
        # @return [Array<String>] unique ids in file order
        def read!(path)
          p = path.to_s.strip
          raise ArgumentError, "input path is required" if p.empty?
          raise EmTools::Core::Errors::ConfigurationError, "input file not found: #{p}" unless File.file?(p)

          seen = {}
          File.foreach(p, chomp: true).filter_map do |line|
            id = line.strip
            next if id.empty? || id.start_with?("#")
            next if seen[id]

            seen[id] = true
            id
          end
        end
      end
    end
  end
end
