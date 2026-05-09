# frozen_string_literal: true

module EmTools
  module Plugins
    module AmazonLowestOffer
      module Queries
        # 应用服务风格的 façade：一次跑完所有已配置站点的评估，返回可写入监控索引的行数据。
        #
        # 限界上下文：**刊登新鲜度 / 可观测性**（offer listing freshness）。
        # 在通用语言里，我们评估：在给定的一组「受关注的商品标识」下，**刊登文档**在各**新鲜度时间窗**
        # 内的分布，以及有多少标识在刊登索引中尚不存在对应文档。
        #
        # 技术实现仍委托 {ListingsCoverageQuery}；本类只提供**业务命名入口**与
        # 「标识来源」的表达。
        class CoverageAssessment
          # 受关注的商品标识从哪里来（与运维 ENV +seed+/+inventory+ 对齐）。
          module WatchedProductIdSource
            # 选品种子文件 / GCS 等（原 +seed+）。
            FROM_PROMOTION_SEED_FEED = :from_promotion_seed_feed
            # 在售库存索引 +em_inventory+ 等（原 +inventory+）。
            FROM_OPERATING_INVENTORY = :from_operating_inventory

            module_function

            def to_id_source(sym)
              case sym.to_sym
              when FROM_PROMOTION_SEED_FEED
                'seed'
              when FROM_OPERATING_INVENTORY
                'inventory'
              else
                allowed = [FROM_PROMOTION_SEED_FEED, FROM_OPERATING_INVENTORY].join(', ')
                raise ArgumentError, "watched_product_id_source must be one of: #{allowed} (got #{sym.inspect})"
              end
            end
          end

          def initialize(search_client:, watched_product_id_source:, **listing_coverage_options)
            @search_client = search_client
            @listing_coverage_options = listing_coverage_options.merge(
              id_source: WatchedProductIdSource.to_id_source(watched_product_id_source)
            )
          end

          # 业务语义：生成「全站点」刊登新鲜度快照行（内部仍为 marketplace 列表上的 ES 查询）。
          def snapshot_rows_for_all_configured_marketplaces(snapshot_captured_at:)
            ListingsCoverageQuery.new(
              es_client: @search_client,
              snapshot_time: snapshot_captured_at,
              **@listing_coverage_options
            ).fetch_all
          end

          # 业务语义：只评估单个站点（例如只跑 DE）。
          def snapshot_rows_for_marketplace(marketplace_code, snapshot_captured_at:)
            mp = marketplace_code.to_s.downcase.strip
            raise ArgumentError, 'marketplace_code is required' if mp.empty?

            ListingsCoverageQuery.new(
              es_client: @search_client,
              marketplaces: [mp],
              snapshot_time: snapshot_captured_at,
              **@listing_coverage_options
            ).fetch_marketplace(mp)
          end
        end
      end
    end
  end
end
