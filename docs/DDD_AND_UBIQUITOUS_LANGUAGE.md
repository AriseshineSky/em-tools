# DDD 视角：业务语言与当前代码的对应关系

Domain-Driven Design 里最有用的是两件事：**通用语言（Ubiquitous Language）** 和 **限界上下文（Bounded Context）**。技术命名（索引名、类名）不必立刻全改，但**新代码、文档、评审、变量名**应优先用业务词，让代码读起来像在描述业务流程。

---

## 1. 本仓库建议的限界上下文（Bounded Context）

| 上下文（业务岛） | 关心什么问题 | 今天主要落在 |
|------------------|--------------|----------------|
| **刊登新鲜度 / 可观测性**（Offer listing freshness） | 给定「要关注的商品标识」，底价刊登在 ES 里是否有文档、按时间窗分布如何 | `LowestOfferListingsCoverageQuery`、`LowestOfferInventoryAsinLoader`、`LowestOfferCoverageSnapshot` |
| **亚马逊上架候选流**（Amazon upload readiness） | 哪些 ASIN 满足时间/标签条件、可进入后续上架管线 | `Amazon::UploadableProductFilter`、`Amazon::UploadProductsFromEs::Runner` |
| **库存同步**（Inventory ingestion） | 把各渠道 CSV/feed 写入 `em_inventory`、淘汰过期批次 | `InventorySync`、`InventorySyncSources` |
| **禁售关键词合规**（Prohibited-keyword policy） | 标题/品牌是否命中禁售词 → 阻断刊登 / 导出 | `Blacklist::Loader`（边界）、`Blacklist::Strategy::TitleBrand`（领域） |
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
| **禁售关键词列表**（prohibited keywords） | 由 Everymarket 后台维护的、不允许刊登的关键词集合 | 上游 API：`/api/v1/blacklist_keywords`；本仓代码：`Core::Blacklist::Loader` |
| **禁售关键词策略**（keyword exclusion policy） | 「给定一个商品文档，根据禁售关键词决定是否阻断」的策略对象 | `Core::Blacklist::Strategy::TitleBrand`（决策） + `Core::Blacklist.build`（工厂）；exporter / importer 用 `policy:` 注入 |
| **被阻断的商品**（blocked / rejected products） | 命中禁售关键词，被排除出当次导出 / 上架的文档 | `policy.blocked?(source)`；side-file `*.blocked.ndjson`（id + title + brand + matched） |

新加功能时：**类名 / 方法名 / PR 标题** 尽量用左列；右列留在实现细节、日志或与运维约定的 ENV。

---

## 3. 分层（与 DDD 经典分层对齐）

| 层 | 职责 | 在本 gem 中的典型形态 |
|----|------|------------------------|
| **领域（Domain）** | 业务规则与名词，不依赖框架 | 值对象、领域服务、**业务命名的 façade**（见 `EmTools::Plugins::Amazon::LowestOffer::Queries::CoverageAssessment`） |
| **应用（Application）** | 用例编排、事务边界 | Rake 任务、`Runner`、`Cli::Commands::*` 里「拼依赖 + 调一次领域」 |
| **基础设施（Infrastructure）** | ES、GCS、HTTP、文件 | `EmTools::Clients::ElasticsearchClient`、`EmTools::Clients::GcsHelper`、`EmTools::Clients::SpreeClient`、`EmTools::Core::Sinks::ElasticsearchBulkSink` |

原则：**领域层不 `puts`、不读 `ARGV`**；CLI / Rake 只做应用层。

---

## 4. 渐进式落地（避免大爆炸重命名）

1. **新能力**：优先在对应插件下用业务类名包一层（如 `lib/em_tools/plugins/<plugin>/queries/`、`/transforms/`、`/sinks/`），内部委托现有类。
2. **旧类名**：可保留为「技术实现」，在类注释第一行写「在通用语言中称为：…」。
3. **对外 API / rake**：稳定优先；准备好后再把 rake 内部改为调用 `Domain::*` façade。  
4. **变量名**：在方法内部用 `watched_product_ids`、`listing_index` 等，比单字母 `mp`/`idx` 更接近业务（长方法里可局部用缩写，但入口参数建议完整）。

---

## 5. 代码入口示例

- **刊登新鲜度评估（领域 façade）**：`EmTools::Plugins::Amazon::LowestOffer::Queries::CoverageAssessment`  
  - 把「受关注的商品标识从哪来」表达为 `:from_promotion_seed_feed` / `:from_operating_inventory`，再映射到现有的 `id_source`。

详细 API 见该类的 YARD 风格注释（源码内）。

---

## 6. 命名决策：为什么"blacklist"留在边界，但领域代码该说"禁售关键词策略"

> 这一节回答的是一类反复出现的复审问题："这个东西真的叫 blacklist 吗？"
> 结论：**保留 + 解释**，不做大爆炸重命名。原因如下。

### 6.1 现状是一个 boundary mismatch

| 层 | 真实含义 | 现在的命名 |
|---|---|---|
| 上游服务（Everymarket admin API） | 后台维护的"禁售关键词"接口 `/api/v1/blacklist_keywords` | API 自己就叫 *blacklist* |
| 本仓边界类（HTTP client / loader） | 拉这个 API、翻页、抽出 keyword 列表 | `EmTools::Core::Blacklist::Loader` |
| 本仓领域类（决策 / 策略） | "title+brand 是否命中禁售关键词" 的判定 | `EmTools::Core::Blacklist::Strategy::TitleBrand`（**这一层叫 blacklist 实际上不准确**） |
| 业务说法 | 禁售合规、刊登/导出阻断 | "禁售关键词"、"keyword exclusion policy" |

英文 *blacklist* 这个词本身在工业界**已经被多重含义污染**（安全黑名单、信用黑名单、滥用拦截等），而我们这里其实是非常具体的"**资质/合规驱动的禁售关键词**"。如果有人空降进项目，光看 `Blacklist` 类名很容易误解为反欺诈/反滥用系统。

### 6.2 为什么不一刀切重命名

| 因素 | 重命名的代价 |
|---|---|
| 上游 API 资源就叫 `blacklist_keywords` | 边界类如果改名 → 看代码的人反而要再做一次"我们的 KeywordPolicy 是不是它对应那个 API"的脑内映射 |
| 运维 ENV 是 `BLACKLIST_API_ENDPOINT/PATH/TOKEN` | 改名要么破坏所有部署，要么得做一长段双向兼容期 |
| CLI `em-tools blacklist download` 已经写进运维 cron / runbook | 同上 |
| `config/blacklist/source_rules.yml`、相关日志 grep 模式 | 改的代码量远超带来的清晰度收益 |

**核心原则**：限界上下文 (Bounded Context) 之间允许语言不一致，但**每跨一层要做显式映射**。我们这里上游就叫 blacklist，让边界类也叫 blacklist 是**正确的**——它精准描述了"这个对象在跟外部哪个东西对话"。

### 6.3 落地约定

我们做了一个 split-name 的最小修正，在领域内部用更精准的词，但不动边界：

| 位置 | 用什么名字 | 理由 |
|---|---|---|
| 上游 HTTP boundary | `Core::Blacklist::Loader`、`BLACKLIST_API_*` ENV、`em-tools blacklist download` | 跟上游 API 的命名一一对齐，**别动** |
| 决策对象（policy） | 注入参数统一叫 `policy:`，不再叫 `blacklist:` / `filter:` | 与 `IndexDumper#policy` 一致；语义是"判断要不要阻断" |
| 插件 CLI 标志 | `--keyword-filter` / `--no-keyword-filter`、`--keywords-path`、`--blocked-output` | 不再叫 `--blacklist-filter`；用动作名 (filter) + 资源名 (keyword) |
| 工厂参数 | `apply_keyword_policy:`（plugin `products_exporter`） | 表达"是否启用禁售关键词策略" |
| 文档 / 日志 / commit 信息 | "禁售关键词策略 / keyword exclusion policy / prohibited keywords" | 业务侧术语 |
| 类注释第一行 | "...the upstream API is named *blacklist*; in the domain we call it a keyword exclusion policy" | 让陌生读者一眼看到映射 |

### 6.4 哪天才该真的重命名

只有当下面这些情况**同时**出现时，才值得做一次 boundary rename：

- 上游 API 自己改了名字（如换成 `prohibited_keywords` endpoint）
- 运维侧已经准备好升级 ENV / cron 脚本
- 项目内 `Blacklist::*` 至少 **5 处**调用要扩展功能（不仅是改名）

在那之前，不要 PR 一个 "rename Blacklist → KeywordPolicy" 的全局替换 —— 这是典型的**符号性整理**，对正确性贡献为零，对代码评审/合并冲突/文件历史搜索全是负贡献。

### 6.5 相关代码入口

- 边界（API client）：`lib/em_tools/core/blacklist/loader.rb`
- 策略（决策）：`lib/em_tools/core/blacklist/strategy/title_brand.rb`
- 立面（facade）：`lib/em_tools/core/blacklist.rb`（`EmTools::Core::Blacklist.build`）
- 注入到 exporter 的例子：`lib/em_tools/plugins/oliveyoung/plugin.rb#products_exporter` 里的 `build_keyword_policy`
- 注入到 dumper 的例子：`lib/em_tools/core/sinks/index_dumper.rb` 的 `policy:` 参数

---

## 7. 延伸阅读

- Eric Evans — *Domain-Driven Design*（战略设计 + 战术模式）
- Vaughn Vernon — *Implementing Domain-Driven Design*（限界上下文与集成）
- 本仓库 `docs/ARCHITECTURE.md`（目录与数据流）
- 本仓库 `docs/PLUGIN_BOUNDARIES.md`（plugin 按渠道划分的设计理由与决策树）
