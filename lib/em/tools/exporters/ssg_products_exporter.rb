# frozen_string_literal: true

module Em
  module Tools
    module Scanners
      class SsgProductsExporter
        def initialize(scanner)
          @scanner = scanner
        end

        def to_jsonl(file_path)
          File.open(file_path, 'w') do |f|
            @scanner.each do |doc|
              f.puts(doc['_source'].to_json)
            end
          end
        end

        def each(&block)
          @scanner.iterate_all(index: 'ssg_products', &block)
        end
      end
    end
  end
end
