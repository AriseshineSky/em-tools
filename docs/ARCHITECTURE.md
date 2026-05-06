# em-tools 架构约定（mono repo，功能清晰）

与 **DDD / 业务语言** 相关的补充说明见 [`docs/DDD_AND_UBIQUITOUS_LANGUAGE.md`](./DDD_AND_UBIQUITOUS_LANGUAGE.md)（限界上下文、通用语言表、分层与渐进迁移）。

---


目标：在**一个仓库**里集中工具代码，同时让每个能力边界清楚、**加功能成本低**、改代码时能快速定位。风格上借鉴 GitLab 类项目常见做法：**分层、小对象、可测试、CLI 只做编排**。

---

## 1. 分层心智模型（数据怎么流动）

把大多数功能看成一条**有向流水线**（不必每处都用 `Processing::Pipeline`，但思维一致）：

| 层 | 职责 | 本仓库中的落点（现状 / 建议） |
|----|------|--------------------------------|
| **Sources 读入** | 从文件、ES、GCS 等拉原始记录或字节流 | `scanners/*`、`clients/elasticsearch_client`、`gcs_blob_fetcher`；新增源放在 `scanners/` 或未来的 `sources/` |
| **Decoding 解码** | 解析 NDJSON/CSV、校验最小结构 → 统一成 `Hash` 等内存结构 | `importers/product_importer#parse_product` 这类方法；复杂时可抽到 `decoding/` |
| **Transform 格式转换 / 清洗** | 字段改名、类型规范化、补默认值、去噪 | 独立小类或 `proc`；与业务规则分离 |
| **Filter 筛选** | 保留 / 丢弃 / 分流（黑名单、价格、类目等） | `filters/*`、`blacklist/*` |
| **Sink 写出** | 写 NDJSON、ES bulk、stdout | `exporters/*`、`elasticsearch_bulk_sink` |

**原则**：I/O 与「业务判断」不要揉在一个大类里；判断逻辑尽量**纯函数化**（输入 hash → 输出 hash 或 `:drop`），方便单测。

---

## 2. 目录与命名空间（Zeitwerk）

根目录为 `lib/em/tools/`，与 `Em::Tools` 对齐。当前及推荐扩展方向：

```
lib/em/tools/
  amazon/           # Amazon / ASIN / upload 相关领域逻辑（含 `AsinProductIndexPipeline`：ASIN 索引 → 产品 mget → 过滤 → bulk 写入目标索引）
  blacklist/        # 黑名单引擎与加载（与具体业务源解耦）
  cli/              # 仅 CLI：OptionParser、读 argv、调用下层
  clients/          # 若放 gem 内：见 lib/em/clients（ES 等）
  exporters/        # 写出侧
  filters/          # 可复用过滤器（组合进 importer 或 pipeline）
  importers/        # 面向「一批业务对象」的编排（可逐步变薄）
  processing/       # 通用：流水线组合（见 Processing::Pipeline）
  domain/           # 业务语言入口（DDD façade）：委托旧实现，渐进对齐通用语言
  scanners/         # 面向「扫描 / 流式读」的源
  …                 # 新领域新建目录，避免塞进 giant 类
```

新增一个能力时的**决策树**：

1. 只多一种**读入**？→ Scanner / Source + 必要时 small client。
2. 只多一种**规则或筛选项**？→ `filters/` 或 `blacklist/` 旁新增类，由 importer 或 pipeline 引用。
3. 只多一条**CLI 命令**？→ `cli/commands/` 下新类，**不写业务**，只组依赖并调用领域对象。
4. 跨多源多筛的**新业务线**？→ 新子目录（如 `inventory_sync.rb` 同级抽成 `inventory/` 模块）+ 一个 `Runner` 作组合根。

---

## 3. 组合根（Runner）与 CLI

- **Runner / Service**：进程内入口，负责拼配置、拼依赖、跑主流程（例：`Amazon::UploadProductsFromEs::Runner`）。
- **CLI**：解析参数、检查 `ENV`、加载 YAML，然后 `Runner.new(...).run!`。

这样 mono repo 里「命令行」与「可复用的库 API」分离，以后 Sidekiq、rake、别的 gem 引用同一套类。

---

## 4. 配置变多时的原则（简要）

- **集中合并**：默认值 → YAML → `ENV` → CLI（你们已在部分命令里实践）。
- **配置**：合并为单一 settings YAML（`gcs` + `inventory_sync` + 连接串）；仅在确有必要时再拆专用 YAML。
- **在边界校验**：进入 Runner 前就把类型与必填项搞清楚。

详见 `docs/LEARNING_SUMMARY.md` 中配置相关小节。

---

## 5. 可组合的处理链：`Em::Tools::Processing::Pipeline`

对「多步转换 + 清洗 + 可插拔」的场景，使用统一契约：

- 每个阶段实现 `call(record, context)`，返回**下一个** `record`（一般为 `Hash`）。
- `context` 用于共享只读配置、logger、计数器对象等；阶段内应**避免**偷偷改全局单例。

示例：

```ruby
pipeline = Em::Tools::Processing::Pipeline.new([
  ->(row, _ctx) { row.transform_values { |v| v.is_a?(String) ? v.strip : v } },
  ->(row, ctx)   { ctx[:blacklist].blocked?(row['title']) ? :drop : row }
])
out = pipeline.call({ 'title' => '  x  ' }, { blacklist: engine })
```

`Pipeline` 在遇到 `:drop` 时可选择短路（当前实现见类注释）；未使用 pipeline 的代码可继续用现有 Importer 风格，**渐进迁移**即可。

---

## 6. 质量与「像 GitLab 一样好维护」的实践清单

| 实践 | 说明 |
|------|------|
| 小 PR / 小提交 | 单 PR 只做一条业务线或一层重构 |
| 每个公共类有 spec | 尤其是过滤器、解码、价格规则 |
| 不藏副作用 | ES 写入、文件写、网络请求集中在 clients / sinks |
| 文档与代码同版本 | 本文件 + `docs/LEARNING_SUMMARY.md` + `config/*.example.yml` |
| RuboCop | CLI 目录已适度放宽 Metrics；**领域类**尽量保持严格 |

---

## 7. Lowest offer 覆盖率：`seed` 与 `em_inventory` 两种 ID 来源

`LowestOfferListingsCoverageQuery` 对 `lowest_offer_listings_<mp>_new` 做时间桶统计时，需要一个 **ASIN 集合** 作为 `terms` 过滤条件。

| 模式 | 环境变量 | 行为 |
|------|------------|------|
| **seed**（默认） | `LOWEST_OFFER_ID_SOURCE` 未设置或 `seed` | 从 `LOWEST_OFFER_SEED_DIR` 或 GCS 读 `amz_<mp>.txt` / `ebay_<mp>.txt`，解析 JSON 列里的 `source_product_id`。 |
| **inventory** | `LOWEST_OFFER_ID_SOURCE=inventory` | 从 ES 索引 `em_inventory`（可改 `LOWEST_OFFER_INVENTORY_INDEX`）扫描文档：`terms` 过滤 `source`（默认字段 `source.keyword`，值见 `LOWEST_OFFER_INVENTORY_AMAZON_SOURCES`，默认 `amazon,amz`），读取 `source_product_id` 并只保留 ASIN 形态；再对 offer 索引用 **同一套** `search_activity` / `search_seed_coverage` 逻辑。 |

可选：`LOWEST_OFFER_INVENTORY_MARKETPLACE_FIELD`（如 `marketplace.keyword`）按当前 `mp` 再收窄一行库存；`LOWEST_OFFER_INVENTORY_MARKETPLACE_VALUE_MODE` 为 `downcase`（默认）或 `upcase`。大批量时可设 `LOWEST_OFFER_INVENTORY_MAX_HITS` 限制扫描条数。

Rake：`rake lowest_offer:publish_snapshot` 在 `inventory` 模式下不再要求本地 seed 目录或 GCS seed，但仍需能访问 ES（含 `em_inventory` 与 `lowest_offer_listings_*`）。

---

## 8. 扩展示例：我要加「某格式 → 清洗 → 黑名单 → NDJSON」

1. 在 `scanners/`（或 `decoding/`）增加 reader，输出 `Enumerator` of `Hash`。
2. 在 `filters/` 增加纯逻辑过滤（或复用 `Blacklist::Engine`）。
3. 用 `Processing::Pipeline` 串 strip、字段映射、黑名单等步骤。
4. 在 `exporters/` 或 CLI 里写 NDJSON 行。
5. 在 `cli/commands/` 增加命令，只做 wiring。

这样**读 / 转 / 滤 / 写**四处都有固定归宿，后续改代码时按层找即可。
