# DDD 视角：业务语言与当前代码的对应关系

Domain-Driven Design 里最有用的是两件事：**通用语言（Ubiquitous Language）** 和 **限界上下文（Bounded Context）**。技术命名（索引名、类名）不必立刻全改，但**新代码、文档、评审、变量名**应优先用业务词，让代码读起来像在描述业务流程。

---

## 1. 本仓库建议的限界上下文（Bounded Context）

| 上下文（业务岛） | 关心什么问题 | 今天主要落在 |
|------------------|--------------|----------------|
| **刊登新鲜度 / 可观测性**（Offer listing freshness） | 给定「要关注的商品标识」，底价刊登在 ES 里是否有文档、按时间窗分布如何 | `LowestOfferListingsCoverageQuery`、`LowestOfferInventoryAsinLoader`、`LowestOfferCoverageSnapshot` |
| **亚马逊上架候选流**（Amazon upload readiness） | 哪些 ASIN 满足时间/标签条件、可进入后续上架管线 | `Amazon::UploadableProductFilter`、`Amazon::UploadProductsFromEs::Runner` |
| **库存同步**（Inventory ingestion） | 把各渠道 CSV/feed 写入 `em_inventory`、淘汰过期批次 | `InventorySync`、`InventorySyncSources` |
| **合规与黑名单**（Compliance / blacklist） | 标题/品牌是否命中禁售词 | `Blacklist::*`、`Filters::BlacklistFilter` |
| **商品导入编排**（Store catalog import） | NDJSON 清洗、价格/类目/黑名单过滤、生成批次 | `Importers::ProductImporter` |

不同上下文之间用 **防腐层**：例如「刊登新鲜度」只依赖 *Elasticsearch 客户端* 和 *配置*，不直接依赖 Spree 模型。

---

## 2. 通用语言表（业务词 ↔ 技术实现）

| 业务说法 | 含义（一句话） | 代码 / 配置中的说法 |
|----------|----------------|---------------------|
| **受关注的商品标识**（watched product id） | 我们本轮统计要圈定的 SKU/ASIN 集合 | seed 里的 `source_product_id`；或 `em_inventory` 的 `source_product_id` |
| **标识来源** | 这批 ID 从哪条业务线来 | `LOWEST_OFFER_ID_SOURCE`：`seed` / `inventory`；领域层见 `WatchedProductIdSource` |
| **选品种子**（promotion seed feed） | 离线/批量的选品结果文件 | `amz_<mp>.txt`、GCS `AMZ_*.txt` |
| **在售库存快照**（operating inventory） | 当前系统认为在售的库存行 | 索引 `em_inventory` 等 |
| **销售渠道**（listing channel） | 库存行上的来源标记，用于只统计亚马逊 | `source` / `source.keyword`；`LOWEST_OFFER_INVENTORY_AMAZON_SOURCES` |
| **刊登文档**（offer listing document） | `lowest_offer_listings_*` 里的一条文档 | ES hit；`asin` / `time` 等字段 |
| **新鲜度时间窗**（freshness windows） | 按 `time` 划分的更新分布 | `time_last_24h` 等聚合桶 |
| **上架候选 ASIN** | 满足流式筛选的亚马逊商品标识 | `UploadableProductFilter` 输出的 ASIN 流 |
| **上架准备运行**（upload preparation run） | Celery 侧一次「从 ES 拉 ASIN 再跑管线」的编排入口 | `UploadProductsFromEs::Runner` |

新加功能时：**类名 / 方法名 / PR 标题** 尽量用左列；右列留在实现细节、日志或与运维约定的 ENV。

---

## 3. 分层（与 DDD 经典分层对齐）

| 层 | 职责 | 在本 gem 中的典型形态 |
|----|------|------------------------|
| **领域（Domain）** | 业务规则与名词，不依赖框架 | 值对象、领域服务、**业务命名的 façade**（见 `Em::Tools::Domain::OfferListingFreshness::CoverageAssessment`） |
| **应用（Application）** | 用例编排、事务边界 | Rake 任务、`Runner`、`Cli::Commands::*` 里「拼依赖 + 调一次领域」 |
| **基础设施（Infrastructure）** | ES、GCS、HTTP、文件 | `Em::Clients::ElasticsearchClient`、`GcsHelper`、`ElasticsearchBulkSink` |

原则：**领域层不 `puts`、不读 `ARGV`**；CLI / Rake 只做应用层。

---

## 4. 渐进式落地（避免大爆炸重命名）

1. **新能力**：优先在 `lib/em/tools/domain/<上下文>/` 下用业务类名包一层，内部委托现有类。  
2. **旧类名**：可保留为「技术实现」，在类注释第一行写「在通用语言中称为：…」。  
3. **对外 API / rake**：稳定优先；准备好后再把 rake 内部改为调用 `Domain::*` façade。  
4. **变量名**：在方法内部用 `watched_product_ids`、`listing_index` 等，比单字母 `mp`/`idx` 更接近业务（长方法里可局部用缩写，但入口参数建议完整）。

---

## 5. 代码入口示例

- **刊登新鲜度评估（领域 façade）**：`Em::Tools::Domain::OfferListingFreshness::CoverageAssessment`  
  - 把「受关注的商品标识从哪来」表达为 `:from_promotion_seed_feed` / `:from_operating_inventory`，再映射到现有的 `id_source`。

详细 API 见该类的 YARD 风格注释（源码内）。

---

## 6. 延伸阅读

- Eric Evans — *Domain-Driven Design*（战略设计 + 战术模式）  
- Vaughn Vernon — *Implementing Domain-Driven Design*（限界上下文与集成）  
- 本仓库 `docs/ARCHITECTURE.md`（目录与数据流）
