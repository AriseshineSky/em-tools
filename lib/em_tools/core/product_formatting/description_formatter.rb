# frozen_string_literal: true

require "cgi"
require "nokogiri"

module EmTools
  module Core
    module ProductFormatting
      # Ruby port of +em_tasks/contexts/product_formatting/product_formatter.py+.
      #
      # Pure HTML/text helpers used by storefront formatters (lotteon, rakuten,
      # naver, watson, ...) when building the +description+ field of an upload
      # payload. No state, no IO; safe to call millions of times per run.
      module DescriptionFormatter
        extend self

        # Strip every +<a>+ tag (and its children) from an HTML fragment, then
        # reserialize. Returns +nil+ when the input is +nil+ / empty so callers
        # can chain +remove_a_tag(remove_a_tag(html))+ idempotently (lotteon and
        # rakuten do this in the Python source).
        #
        # Mirrors lxml's +html.fromstring+ + +etree.tostring(method="html",
        # pretty_print=True)+ behavior using Nokogiri's HTML parser. The output
        # is pretty-printed HTML, not XHTML.
        #
        # @param description [String, nil]
        # @return [String, nil]
        def remove_a_tag(description)
          return if description.nil?
          return if description.respond_to?(:empty?) && description.empty?

          fragment = Nokogiri::HTML.fragment(description.to_s)
          fragment.css("a").each(&:unlink)
          fragment.to_html(
            indent: 2,
            save_with: Nokogiri::XML::Node::SaveOptions::DEFAULT_HTML |
              Nokogiri::XML::Node::SaveOptions::FORMAT,
          )
        end

        # Build a +<ul><li>name: value</li>...</ul>+ description from a list of
        # +{ "name" => ..., "value" => ... }+ specifications. Items with empty
        # name or value are skipped. Returns +""+ when nothing usable is found
        # (matches Python's implicit empty-string return).
        #
        # Names and values are HTML-escaped so storefront descriptions don't
        # accidentally inherit raw +<+ / +&+ characters that the Python version
        # passed through verbatim.
        #
        # @param specifications [Array<Hash>, nil]
        # @return [String]
        def generate_description_by_specifications(specifications)
          return "" if specifications.nil? || !specifications.respond_to?(:each)

          items = specifications.each_with_object([]) do |spec, acc|
            next unless spec.is_a?(Hash)

            name = spec["name"].to_s.strip
            value = spec["value"].to_s.strip
            next if name.empty? || value.empty?

            acc << "<li>#{CGI.escapeHTML(name)}: #{CGI.escapeHTML(value)}</li>"
          end

          items.empty? ? "" : "<ul>#{items.join}</ul>"
        end
      end
    end
  end
end
