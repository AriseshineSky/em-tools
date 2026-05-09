# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Product dimension check: reject products whose largest side exceeds +DIMENSION_MAX_INCH+ inches.
      # rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists -- ported 1:1 from em-tasks; preserve decision-tree shape.
      class DimensionFilter < Strategy
        DIMENSION_MAX_INCH = 12

        FLEXIBLE_DISPLAY_PRODUCT_TYPES = %w[
          NECKLACE BRACELET ANKLET CHARM PENDANT CURTAIN BLANKET
        ].to_set.freeze

        DIM_KEYS = %i[width height length diameter].freeze

        # Multipliers from various unit names to inches.
        UNIT_TO_INCH = {
          'inches' => 1.0, 'inch' => 1.0, 'in' => 1.0,
          'feet' => 12.0, 'foot' => 12.0, 'ft' => 12.0,
          'yard' => 36.0, 'yards' => 36.0, 'yd' => 36.0,
          'centimeters' => (1.0 / 2.54), 'centimeter' => (1.0 / 2.54), 'cm' => (1.0 / 2.54),
          'millimeters' => (1.0 / 25.4), 'millimeter' => (1.0 / 25.4), 'mm' => (1.0 / 25.4),
          'meters' => (100.0 / 2.54), 'meter' => (100.0 / 2.54), 'm' => (100.0 / 2.54)
        }.freeze

        def initialize(dimension_max: nil, **opts)
          super(**opts)
          @dimension_max = dimension_max || DIMENSION_MAX_INCH
        end

        def check(product)
          product = product.is_a?(Hash) ? product : {}
          dimensions, source = dimensions_with_source(product)
          return passed_result if skip_display_only_dimension?(product, source)
          return passed_result if dimensions.nil?

          width = dimensions[:width]
          height = dimensions[:height]
          length = dimensions[:length]
          diameter = dimensions[:diameter]

          has_full_lwh = width && height && length
          has_diameter = !diameter.nil?
          return passed_result unless has_full_lwh || has_diameter

          if oversize?(width, height, length, diameter, has_full_lwh, has_diameter)
            return failed_result(
              '[OverSize]',
              message: "Product is over size #{width}x#{height}x#{length} (diameter: #{diameter})"
            )
          end

          passed_result
        end

        # Returns +[dimensions_hash_or_nil, source_label_or_nil]+. Public for parity with the Python helper.
        def dimensions_with_source(product)
          extractors.each do |source_name, method_name|
            candidate = send(method_name, product)
            next unless candidate.is_a?(Hash)
            next unless DIM_KEYS.any? { |k| candidate.key?(k.to_s) || candidate.key?(k) }

            return [normalize(candidate), source_name]
          end
          [nil, nil]
        end

        private

        def extractors
          [
            ['package', :package_dimensions],
            ['raw', :raw_dimensions],
            ['item_length_width_height', :item_length_width_height],
            ['item_width_height', :width_height_attributes],
            ['item_length_width', :length_width_attributes],
            ['item_diameter', :item_diameter_attributes],
            ['display', :item_display_dimensions]
          ]
        end

        def oversize?(width, height, length, diameter, has_full_lwh, has_diameter)
          (has_full_lwh && [width, height, length].any? { |v| v > @dimension_max }) ||
            (has_diameter && diameter > @dimension_max)
        end

        def skip_display_only_dimension?(product, source)
          return false if %w[package raw].include?(source.to_s) || source.nil?

          Array(product['productTypes']).any? do |item|
            item.is_a?(Hash) && FLEXIBLE_DISPLAY_PRODUCT_TYPES.include?(item['productType'])
          end
        end

        def normalize(dims)
          DIM_KEYS.each_with_object({}) do |key, acc|
            value = dims[key.to_s] || dims[key]
            acc[key] = convert_to_inch(value)
          end
        end

        def convert_to_inch(dim)
          return nil unless dim.is_a?(Hash)

          value = dim['value'] || dim[:value]
          value = dim['decimal_value'] || dim[:decimal_value] if value.nil?
          unit = (dim['unit'] || dim[:unit]).to_s.downcase
          return nil if value.nil? || unit.empty?

          multiplier = UNIT_TO_INCH[unit]
          return nil unless multiplier

          (value.to_f * multiplier).round(2)
        end

        def attribute(product, key)
          attrs = product['attributes'] || {}
          attrs[key]
        end

        def first_attribute_entry(product, key)
          list = attribute(product, key)
          return nil unless list.is_a?(Array) && !list.empty?

          list.first
        end

        def item_diameter_attributes(product)
          entry = first_attribute_entry(product, 'item_diameter')
          return nil unless entry.is_a?(Hash)

          value = entry['value'] || entry['decimal_value']
          return nil if value.nil?

          { 'diameter' => { 'value' => value, 'unit' => entry['unit'] || 'millimeters' } }
        end

        def item_length_width_height(product)
          dims = first_attribute_entry(product, 'item_length_width_height')
          return nil unless dims.is_a?(Hash)

          extract_typed_dims(dims, %w[width height length], 'centimeters')
        end

        def item_display_dimensions(product)
          dims = first_attribute_entry(product, 'item_display_dimensions')
          return nil unless dims.is_a?(Hash)

          result = extract_typed_dims(dims, %w[width height length], 'millimeters')
          return nil unless result

          # display 尺寸仅在三边都存在时才用于超长判断
          return result if %w[width height length].all? { |k| result[k] }

          nil
        end

        def width_height_attributes(product)
          entry = first_attribute_entry(product, 'item_width_height')
          return nil unless entry.is_a?(Hash)

          { 'width' => entry['width'], 'height' => entry['height'], 'length' => nil }
        end

        def length_width_attributes(product)
          entry = first_attribute_entry(product, 'item_length_width')
          return nil unless entry.is_a?(Hash)

          extract_typed_dims(entry, %w[length width height], 'centimeters')
        end

        def package_dimensions(product)
          dims = product['item_package_dimensions'] || attribute(product, 'item_package_dimensions')
          dims = dims.first if dims.is_a?(Array)
          return dims if dims.is_a?(Hash)

          legacy_amazon_dims(attribute(product, 'PackageDimensions'))
        end

        def raw_dimensions(product)
          raw_list = product['dimensions']
          if raw_list.is_a?(Array) && !raw_list.empty?
            entry = raw_list.first
            dims = entry['package'] || entry['item']
            dims = dims.first if dims.is_a?(Array)
            return dims if dims.is_a?(Hash)
          end

          legacy_amazon_dims(attribute(product, 'ItemDimensions'))
        end

        def legacy_amazon_dims(legacy)
          return nil unless legacy.is_a?(Hash)

          dims = {}
          %w[Width Height Length Weight].each do |k|
            entry = legacy[k]
            next unless entry.is_a?(Hash)

            default_unit = k == 'Weight' ? 'pounds' : 'inches'
            unit = entry.dig('Units', 'value') || default_unit
            dims[k.downcase] = { 'value' => entry['value'], 'unit' => unit }
          end
          dims.empty? ? nil : dims
        end

        def extract_typed_dims(source, keys, default_unit)
          result = {}
          keys.each do |key|
            dim = source[key]
            next unless dim.is_a?(Hash) && dim.key?('value')

            result[key] = { 'value' => dim['value'], 'unit' => dim['unit'] || default_unit }
          end
          result.empty? ? nil : result
        end
      end
      # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists
    end
  end
end
