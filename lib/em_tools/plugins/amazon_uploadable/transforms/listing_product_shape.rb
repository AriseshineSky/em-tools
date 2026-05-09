# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonUploadable
      module Transforms
        module ListingProductShape
          MARKETPLACE_META = {
            'jp' => { code: 'X04', host: 'https://www.amazon.co.jp' },
            'uk' => { code: 'X05', host: 'https://www.amazon.co.uk' },
            'us' => { code: 'X06', host: 'https://www.amazon.com' },
            'tr' => { code: 'X07', host: 'https://www.amazon.com.tr' },
            'de' => { code: 'X08', host: 'https://www.amazon.de' },
            'ae' => { code: 'X74', host: 'https://www.amazon.ae' },
            'mx' => { code: 'X75', host: 'https://www.amazon.com.mx' },
            'in' => { code: 'X76', host: 'https://www.amazon.in' },
            'it' => { code: 'X46', host: 'https://www.amazon.it' },
            'ca' => { code: 'X77', host: 'https://www.amazon.ca' },
            'fr' => { code: 'X09', host: 'https://www.amazon.fr' }
          }.freeze

          module_function

          def from_es_product(data, marketplace:, cli_source: nil, cli_source_code: nil)
            mp = marketplace.to_s.downcase.strip
            meta = MARKETPLACE_META[mp] || { code: 'X06', host: 'https://www.amazon.com' }
            asin = pick(data, 'asin').to_s.strip.upcase
            src = cli_source.to_s.strip.empty? ? "AMZ_#{mp.upcase}" : cli_source.to_s.strip
            sku_prefix = meta[:code]

            {
              'source' => src,
              'source_code' => cli_source_code.to_s,
              'source_product_id' => asin,
              'source_product_url' => "#{meta[:host]}/dp/#{asin}",
              'has_only_default_variant' => true,
              'existances' => true,
              'title' => pick(data, 'title').to_s,
              'description' => pick(data, 'description').to_s,
              'brand' => extract_brand(data),
              'categories' => extract_categories(data),
              'images' => extract_images(data),
              'specifications' => pick(data, 'specifications'),
              'options' => [],
              'sku' => "#{sku_prefix}-#{asin}",
              'upc' => extract_upc(data),
              'weight' => pick(data, 'weight'),
              'returnable' => nil
            }
          end

          def pick(h, key)
            return nil unless h.is_a?(Hash)

            h[key] || h[key.to_sym]
          end

          def extract_brand(data)
            b = pick(data, 'brand')
            return b.to_s if b && !b.to_s.strip.empty?

            attrs = pick(data, 'attributes')
            return '' unless attrs.is_a?(Hash)

            brand = attrs.dig('Brand', 'value') || attrs.dig(:Brand, :value)
            b = brand.to_s
            b = b.gsub(/Visit the|Amazon|amazon/i, '').strip if b
            b
          end

          def extract_categories(data)
            if data['categories'].is_a?(Array) && data['categories'].any?
              return data['categories'].filter_map { |c| c['cat_name'] || c[:cat_name] }
            end

            %w[top_category second_category third_category].filter_map { |k| pick(data, k) }
          end

          def extract_images(data)
            imgs = pick(data, 'images')
            return imgs.to_s if imgs.is_a?(String) && !imgs.empty?

            arr = pick(data, 'image_urls') || pick(data, 'images')
            return '' unless arr.is_a?(Array)

            arr.filter_map { |e| e.is_a?(String) ? e : e['url'] || e[:url] }.join(';')
          end

          def extract_upc(data)
            ids = pick(data, 'identifiers')
            return nil unless ids.is_a?(Array)

            ids.each do |block|
              next unless block.is_a?(Hash) && block['identifiers'].is_a?(Array)

              block['identifiers'].each do |id|
                next unless id.is_a?(Hash)

                t = id['identifierType'] || id[:identifierType]
                v = id['identifier'] || id[:identifier]
                return v if t.to_s.match?(/GTIN|UPC/i)
              end
            end
            nil
          end
        end
      end
    end
  end
end
