module Em::Tools::Scanners
  class SsgProductsScanner
    def initialize(client)
      @client = cline
    end

    def each
      @client.iterate_all(index: "ssg_products") do |doc|
        yield doc
      end
    end
  end
end
