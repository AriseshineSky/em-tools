# frozen_string_literal: true

module EmTools
  module Core
    module Rules
      # Block products by disallowed Amazon category IDs.
      class CategoryIdFilter < Strategy
        GLOBAL_BLOCKED_CATEGORY_IDS = Set.new.freeze

        BLOCKED_CATEGORY_IDS_BY_MARKETPLACE_ID = {
          # DE
          "A1PA6795UKMFR9" => Set[
            "64274031",     # Sex & Sensuality
            "2727360031",   # Novelty & Games
            "2727361031",   # Edible Underwear
            "2970847031", # Lighters
          ],
          # UK
          "A1F83G8C2ARO7P" => Set[
            "3076594031", # Camping Lighters & Fire Starters
          ],
          # JP
          "A1VC38T7YXB528" => Set[
            "169939011",    # Intimate Care
            "8486179051",   # Douches & Enemas
            "14917031",     # Replacement Fuel
            "15326261",     # Gas Cartridges
            "15348551",     # Gas Lighters
            "2201151051", # Camp Kitchen
          ],
          # US
          "ATVPDKIKX0DER" => Set[
            "10342347011", # Lighters & Matches
            "10342354011", # Lighters
          ],
          # IN
          "A21TJRUUN4KGV" => Set[
            "1374574031", # Lighters & Matches
          ],
        }.freeze

        MARKETPLACE_ID_KEYS = [
          "identifiers",
          "productTypes",
          "relationships",
          "summaries",
          "classifications",
          "dimensions",
          "salesRanks",
        ].freeze

        def check(product)
          product = product.is_a?(Hash) ? product : {}
          category_ids = extract_category_ids(product)
          return passed_result if category_ids.empty?

          marketplace_id = extract_marketplace_id(product)
          blocked_ids = blocked_ids_for(marketplace_id)

          hit_ids = (category_ids & blocked_ids).to_a.sort
          return passed_result if hit_ids.empty?

          failed_result("[CategoryIdBlocked:#{hit_ids.join(",")}]")
        end

        private

        def blocked_ids_for(marketplace_id)
          ids = GLOBAL_BLOCKED_CATEGORY_IDS.dup
          extra = marketplace_id && BLOCKED_CATEGORY_IDS_BY_MARKETPLACE_ID[marketplace_id]
          ids.merge(extra) if extra
          ids
        end

        def extract_marketplace_id(product)
          MARKETPLACE_ID_KEYS.each do |key|
            values = product[key]
            next unless values.is_a?(Array)

            values.each do |item|
              next unless item.is_a?(Hash)

              marketplace_id = item["marketplaceId"] || item[:marketplaceId]
              return marketplace_id.to_s if marketplace_id
            end
          end
          nil
        end

        def extract_category_ids(product)
          category_ids = Set.new
          collect_categories!(category_ids, product["categories"])
          collect_sales_ranks!(category_ids, product["salesRanks"])
          collect_summary_browse_ids!(category_ids, product["summaries"])
          category_ids
        end

        def collect_categories!(category_ids, items)
          Array(items).each do |item|
            next unless item.is_a?(Hash)

            cat_id = item["cat_id"] || item[:cat_id]
            category_ids << cat_id.to_s if cat_id
          end
        end

        def collect_sales_ranks!(category_ids, items)
          Array(items).each do |rank|
            next unless rank.is_a?(Hash)

            Array(rank["classificationRanks"]).each do |cls|
              next unless cls.is_a?(Hash)

              cls_id = cls["classificationId"]
              category_ids << cls_id.to_s if cls_id
            end
          end
        end

        def collect_summary_browse_ids!(category_ids, items)
          Array(items).each do |summary|
            next unless summary.is_a?(Hash)

            browse = summary["browseClassification"]
            next unless browse.is_a?(Hash)

            cls_id = browse["classificationId"]
            category_ids << cls_id.to_s if cls_id
          end
        end
      end
    end
  end
end
