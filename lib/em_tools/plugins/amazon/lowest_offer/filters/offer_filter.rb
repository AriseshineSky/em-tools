# frozen_string_literal: true

module EmTools
  module Plugins
    module Amazon
      module LowestOffer
        module Filters
          # Ruby port of +dropshipping/utils/offer_filters.py::LowestOfferListingOfferFilter+ — applies
          # seller-side conditions (FBA, rating, feedback, domestic, shipping_time, subcondition,
          # min price for FBA) to a list of offers, sorts by landed price, then picks one offer
          # according to +provider_type+ ("min" / "max" / "fba" / "avg"). Used by
          # {EmTools::Plugins::Amazon::LowestOffer::Services::OfferService} after parsing the JSON
          # +offers+ array from a +lowest_offer_listings_<mp>_<condition>+ ES doc.
          #
          # Only +LowestOfferListingOfferFilter+ is ported; +BuyBoxOfferFilter+ has no caller in this
          # gem so it is intentionally omitted (per "只提取我用到的方法和函数"). # -- mirrors Python rule surface; splitting hurts traceability.
          class OfferFilter
            # Mirrors +dropshipping.mws.SUBCONDITION_MAPPING+ exactly.
            SUBCONDITION_MAPPING = {
              "new" => 100,
              "mint" => 90,
              "like_new" => 90,
              "likenew" => 90,
              "very_good" => 81,
              "verygood" => 80,
              "good" => 70,
              "acceptable" => 60,
              "poor" => 50,
              "club" => 40,
              "oem" => 30,
              "warranty" => 25,
              "refurbishedwarranty" => 20,
              "refurbished_warranty" => 21,
              "refurbished" => 15,
              "open_box" => 10,
              "openbox" => 11,
              "other" => 0,
            }.freeze

            CONDITION_KEYS = [
              :rating,
              :feedback,
              :domestic,
              :shipping_time,
              :condition,
              :subcondition,
              :fba,
              :offers,
              :price,
              :expire_hour,
              :picked_count,
              :provider_type,
            ].freeze

            DEFAULT_PROVIDER_TYPE = "min"
            DEFAULT_PICKED_COUNT = 2
            DEFAULT_MIN_OFFERS = 1

            attr_reader :conds, :subcondition_strategy

            # Accepts each filter condition as a keyword argument. Any unknown keyword raises
            # +ArgumentError+ to surface typos early. The single +strategies:+ hash carries
            # behavior toggles like +subcondition_strategy:+ (+"ge"+ / +"eq"+, default +"ge"+).
            #
            # Recognized condition keys (all optional, all default to +nil+ = "no constraint"):
            # +:rating+, +:feedback+, +:domestic+, +:shipping_time+ (max minutes), +:condition+,
            # +:subcondition+ (numeric threshold from {SUBCONDITION_MAPPING}), +:fba+ (true/false),
            # +:offers+ (min count required to pass), +:price+ (FBA min price floor),
            # +:expire_hour+, +:picked_count+, +:provider_type+ ("min"/"max"/"fba"/"avg"). # -- explicit kwarg validation mirrors Python conds dict
            def initialize(strategies: {}, **conds)
              unknown = conds.keys.reject { |k| CONDITION_KEYS.include?(k) }
              raise ArgumentError, "unknown OfferFilter conds: #{unknown.inspect}" if unknown.any?

              @conds = CONDITION_KEYS.to_h { |k| [k, conds[k]] }
              strat = strategies.is_a?(Hash) ? normalize_keys(strategies) : {}
              sub_strat = strat[:subcondition_strategy].to_s.downcase
              @subcondition_strategy = ["eq", "ge"].include?(sub_strat) ? sub_strat : "ge"
            end
            # rubocop:enable Metrics/AbcSize

            # Returns the picked offer hash (with +offers+ count merged in) or +nil+ when no offer
            # passes the filter / not enough offers remain. Mirrors Python's +filter()+.
            # rubocop:disable Metrics/AbcSize
            def filter(offers)
              filtered = filter_all(offers).sort_by { |o| offer_price(o) }
              count = filtered.size

              min_count = (@conds[:offers] || DEFAULT_MIN_OFFERS).to_i
              return if count < min_count

              picked_count = [(@conds[:picked_count] || DEFAULT_PICKED_COUNT).to_i, count].min
              picked = filtered.first(picked_count)
              provider_type = (@conds[:provider_type] || DEFAULT_PROVIDER_TYPE).to_s

              case provider_type
              when "min"
                dup_offer(picked.first)
              when "max"
                dup_offer(picked.last)
              when "fba"
                fba_pick = picked.find { |o| o["fba"] == true }
                if fba_pick
                  offer = dup_offer(fba_pick)
                  offer["offers"] = count
                  return offer
                end
                build_average_offer(picked, count)
              else
                build_average_offer(picked, count)
              end
            end
            # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

            # Returns the subset of +offers+ that pass each enabled seller-side check. Mirrors
            # Python's +filter_all()+.
            # rubocop:disable Metrics/CyclomaticComplexity
            def filter_all(offers)
              list = Array(offers).grep(Hash)
              list.select do |offer|
                next false unless fba_match?(offer)
                next false unless price_floor_match?(offer)
                next false unless domestic_match?(offer)
                next false unless shipping_time_match?(offer)
                next false unless rating_and_feedback_match?(offer)
                next false unless subcondition_match?(offer)

                true
              end
            end
            # rubocop:enable Metrics/CyclomaticComplexity

            def expire_hour
              @conds[:expire_hour]
            end

            private

            def normalize_keys(hash)
              hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
            end

            def offer_price(offer)
              offer["price"] || 0
            end

            def dup_offer(offer)
              offer.is_a?(Hash) ? offer.dup : nil
            end

            def fba_match?(offer)
              return true if @conds[:fba].nil?

              offer["fba"] == @conds[:fba]
            end

            # Python rule: skip FBA offers whose price <= configured min `price`.
            def price_floor_match?(offer)
              return true if @conds[:price].nil?
              return true unless offer["fba"]

              offer["price"].to_f > @conds[:price].to_f
            end

            def domestic_match?(offer)
              return true if @conds[:domestic].nil?

              ships_from = offer["ships_from"]
              if ships_from && (ships_from == "gb")
                offer["ships_from"] = "uk"
                offer["domestic"] = true if offer["country"] == "uk"
              end

              return true unless offer.key?("domestic")

              offer["domestic"] == @conds[:domestic]
            end

            def shipping_time_match?(offer)
              return true if @conds[:shipping_time].nil?

              shipping_time = offer["shipping_time"] || {}
              availability_type = shipping_time["availability_type"]
              return false if availability_type && !availability_type.to_s.downcase.include?("now")

              min = shipping_time["min"]
              return true if min.nil?

              min.to_i <= @conds[:shipping_time].to_i
            end

            # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
            def rating_and_feedback_match?(offer)
              return true if offer.key?("buybox")
              return true if offer["fba"] == true

              if @conds[:rating]
                rating = extract_rating(offer["rating"])
                return false if rating.nil? || rating < @conds[:rating]
              end

              if @conds[:feedback]
                feedback = offer["feedback"]
                return false if feedback.nil? || feedback.to_i < @conds[:feedback].to_i
              end

              true
            end
            # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

            def extract_rating(value)
              case value
              when Hash then value["min"]
              when Numeric then value.to_i
              when nil then nil
              when String then Integer(value, 10)
              end
            rescue ArgumentError, TypeError
              nil
            end

            def subcondition_match?(offer)
              return true if @conds[:subcondition].nil?

              sub = offer["subcondition"].to_s.downcase
              return false if sub.empty?
              return true unless SUBCONDITION_MAPPING.key?(sub)

              value = SUBCONDITION_MAPPING[sub]
              if @subcondition_strategy == "ge"
                value >= @conds[:subcondition].to_i
              else
                value == @conds[:subcondition].to_i
              end
            end

            def build_average_offer(picked, count)
              return if picked.empty?

              offer = dup_offer(picked.first) || {}
              picked_count = picked.size
              offer["product_price"] = round2(avg(picked, "product_price", picked_count))
              offer["shipping_price"] = round2(avg(picked, "shipping_price", picked_count))
              offer["price"] = round2(avg(picked, "price", picked_count))
              offer["offers"] = count
              offer
            end

            def avg(picked, key, picked_count)
              picked.sum { |o| (o[key] || 0).to_f } / picked_count
            end

            def round2(value)
              value.is_a?(Numeric) ? value.round(2) : value
            end
          end
          # rubocop:enable Metrics/ClassLength
        end
      end
    end
  end
end
