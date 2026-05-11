# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Hazardous material / restricted-shipping detection. Targets aerosols, flammable sprays,
      # pressurized cans, perfumes, fuel containers, batteries, etc. that are unsafe for cross-border air shipping. # -- ported 1:1 from em-tasks; preserve decision-tree shape.
      class HazmatFilter < Strategy
        ALLOW_PURFUME_MARKETPLACE_IDS = ["A2VIGQ35RCS4UG"].freeze

        AEROSOL_KEYWORDS = [
          "aerosol",
          "spray",
          "mist",
          "mousse",
          "carbonated",
          "炭酸",
          "スプレー",
          "ムース",
        ].freeze

        FLAMMABLE_PROPELLANTS = ["butane", "propane", "isobutane", "lpg"].freeze
        AEROSOL_FORMS = ["aerosol", "mousse", "foam", "spray", "mist"].freeze
        HAZMAT_PRODUCT_TYPES = ["SOLID_FIRE_FUEL", "PESTICIDE"].freeze

        FUEL_KEYWORDS = Set.new(["fuel", "gas", "butane", "propane", "lpg", "cartridge", "canister"]).freeze
        FUEL_CATEGORIES = Set.new(["GAS CARTRIDGES", "REPLACEMENT FUEL", "CAMP KITCHEN"]).freeze

        CHEMICAL_PUTTY_KEYWORDS = Set.new(["putty", "epoxy", "resin", "hardener"] + ["repair compound"]).freeze

        SOLID_FIRE_FUEL_FALSE_POSITIVE_KEYWORDS = Set.new([
          "sheet",
          "mat",
          "blanket",
          "fireproof",
          "flame retardant",
          "heat resistant",
          "spatter",
          "welding",
          "glass fiber",
          "fiberglass",
        ]).freeze

        CHEMICAL_WARNING_KEYWORDS = Set.new([
          "avoid fire",
          "danger",
          "do not inhale",
          "use outdoors",
          "flammable",
          "keep away from heat",
        ]).freeze

        ADHESIVE_KEYWORDS = Set.new(["adhesive", "glue", "super glue", "cyanoacrylate", "sealant"]).freeze
        ADHESIVE_PRODUCT_TYPES = Set.new(["BONDING_ADHESIVES", "ADHESIVES"]).freeze

        HIGH_RISK_HAZMAT_CLASSES = Set.new(["2", "2.1", "3"]).freeze

        def initialize(**opts)
          super
          @foam_filter = FoamFilter.new
        end

        def check(product)
          product = normalize_product(product)
          text = product["title"].to_s.downcase
          item_form = item_form_text(product)
          category = product["product_type"].to_s.downcase

          foam_result = @foam_filter.check(product)
          return foam_result unless foam_result[:passed]

          if (hit = aerosol_keyword_hit(text))
            return failed_result("[HazmatKeyword:#{hit}]")
          end

          if (pt = hazmat_product_type_hit(product))
            return failed_result("[#{pt}]")
          end

          if (form = aerosol_form_hit(item_form))
            return failed_result("[HazmatAerosolForm:#{form}]")
          end

          if (gas = flammable_propellant_hit(text))
            return failed_result("[HazmatPropellant:#{gas}]")
          end

          return failed_result("[HazmatHairFoam]") if category.include?("hair") && text.include?("foam")
          return failed_result("[Perfume]") if perfume?(product)
          return failed_result("[CompressedGas]") if compressed_gas?(product)
          return failed_result("[IncludeBattery]") if include_battery?(product)

          if (cls = blocking_hazmat(product))
            return failed_result("[HazmatFuel:#{cls}]")
          end

          return failed_result("[RestrictedChemical:Adhesive]") if hazardous_adhesive?(product)
          return failed_result("[RestrictedChemical:EpoxyPutty]") if restricted_chemical?(product)

          passed_result
        end

        # Public helpers (mirror the Python module so other rules can reuse them).

        def hazmat_class(product)
          @foam_filter.hazmat_class(product)
        end

        def marketplace_id(product)
          ["identifiers", "productTypes", "relationships"].each do |key|
            Array(product[key]).each do |value|
              next unless value.is_a?(Hash)

              return value["marketplaceId"] if value["marketplaceId"]
            end
          end
          nil
        end

        private

        def normalize_product(product)
          return {} unless product.is_a?(Hash)

          dup = product.dup
          dup["categories"] ||= []
          dup["productTypes"] ||= []
          attrs = (dup["attributes"] || {}).dup
          attrs["bullet_point"] ||= []
          attrs["hazmat"] ||= []
          attrs["batteries_included"] ||= []
          attrs["item_form"] ||= []
          dup["attributes"] = attrs
          dup
        end

        def item_form_text(product)
          parts = []
          top = product["item_form"]
          case top
          when String
            parts << top unless top.strip.empty?
          when Array
            top.each { |x| parts << x["value"].to_s if x.is_a?(Hash) && !x["value"].nil? }
          end
          Array(product.dig("attributes", "item_form")).each do |x|
            parts << x["value"].to_s if x.is_a?(Hash) && !x["value"].nil?
          end
          parts.join(" ").downcase
        end

        def aerosol_keyword_hit(text)
          AEROSOL_KEYWORDS.find { |k| text.include?(k.downcase) }
        end

        def hazmat_product_type_hit(product)
          product_types(product).find do |pt|
            next false unless HAZMAT_PRODUCT_TYPES.include?(pt)
            next false if pt == "SOLID_FIRE_FUEL" && false_positive_solid_fire_fuel?(product)

            true
          end
        end

        def aerosol_form_hit(item_form)
          AEROSOL_FORMS.find { |f| item_form.include?(f) }
        end

        def flammable_propellant_hit(text)
          FLAMMABLE_PROPELLANTS.find { |gas| text.include?(gas) }
        end

        def perfume?(product)
          return false if ALLOW_PURFUME_MARKETPLACE_IDS.include?(marketplace_id(product))
          return true if product_types(product).include?("PERSONAL_FRAGRANCE")

          categories_upcase(product).any? { |c| c.include?("FRAGRANCE") || c.include?("EAU DE TOILETTE") }
        end

        def compressed_gas?(product)
          cls = nil
          name = nil
          Array(product.dig("attributes", "hazmat")).each do |item|
            next unless item.is_a?(Hash)

            value = item["value"].to_s.upcase
            case item["aspect"]
            when "transportation_regulatory_class"
              cls = value
            when "proper_shipping_name"
              name = value
            end
          end
          cls == "2.1" && name == "RECEPTACLES, SMALL, CONTAINING GAS"
        end

        def include_battery?(product)
          return false if ALLOW_PURFUME_MARKETPLACE_IDS.include?(marketplace_id(product))

          Array(product.dig("attributes", "batteries_included")).any? do |flag|
            flag.is_a?(Hash) && flag["value"] == true
          end
        end

        def blocking_hazmat(product)
          cls = hazmat_class(product)
          return unless cls
          return unless HIGH_RISK_HAZMAT_CLASSES.include?(cls)

          fuel_container?(product) ? cls : nil
        end

        def fuel_container?(product)
          text = collect_text(product)
          return true if FUEL_KEYWORDS.any? { |k| text.include?(k) }

          categories = categories_upcase(product)
          return true if categories.any? { |c| FUEL_CATEGORIES.include?(c) }

          !product.dig("attributes", "fuel_type").to_s.empty?
        end

        def hazardous_adhesive?(product)
          text = collect_text(product)
          types = product_types(product).to_set

          has_adhesive_signal = ADHESIVE_KEYWORDS.any? { |k| text.include?(k) } ||
            !!types.intersect?(ADHESIVE_PRODUCT_TYPES)
          return false unless has_adhesive_signal
          return false unless hazmat_class(product) == "3"

          shipping_name = ""
          Array(product.dig("attributes", "hazmat")).each do |item|
            next unless item.is_a?(Hash) && item["aspect"] == "proper_shipping_name"

            shipping_name = item["value"].to_s.upcase
            break
          end

          shipping_name.include?("ADHESIVE") || !!types.intersect?(ADHESIVE_PRODUCT_TYPES)
        end

        def restricted_chemical?(product)
          text = collect_text(product)
          return false unless CHEMICAL_PUTTY_KEYWORDS.any? { |k| text.include?(k) }
          return true if CHEMICAL_WARNING_KEYWORDS.any? { |k| text.include?(k) }

          hazmat_class(product) == "3"
        end

        def false_positive_solid_fire_fuel?(product)
          text = collect_text(product)
          return false if text.empty?

          shielding = SOLID_FIRE_FUEL_FALSE_POSITIVE_KEYWORDS.any? { |k| text.include?(k) }
          fuel = FUEL_KEYWORDS.any? { |k| text.include?(k) }
          shielding && !fuel
        end

        def collect_text(product)
          title = product["title"].to_s
          bullets = Array(product.dig("attributes", "bullet_point")).filter_map do |bp|
            bp.is_a?(Hash) ? bp["value"] : nil
          end.join(" ")
          "#{title} #{bullets}".downcase
        end

        def product_types(product)
          Array(product["productTypes"]).filter_map do |pt|
            next unless pt.is_a?(Hash)

            pt["productType"].to_s.upcase
          end
        end

        def categories_upcase(product)
          Array(product["categories"]).filter_map do |c|
            next unless c.is_a?(Hash)

            c["cat_name"].to_s.upcase
          end
        end
      end
      # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Layout/LineLength
    end
  end
end
