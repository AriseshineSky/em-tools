# 从 `em-tools` 项目里能学到什么

本文档面向希望理解本仓库设计与实践的读者，总结当前架构里值得学习的点，并与本次从 **em-celery**（`em_celery/tools/spree/amz_upload_products_from_es.py`）迁移到 Ruby 的工作联系起来。

---

## 1. 用 Zeitwerk 管理应用内代码

本项目不是 gem；入口是 `bin/em-tools`，它把 `lib/` 加进 `$LOAD_PATH` 后 `require "em_tools"`。`lib/em_tools.rb` 使用 `Zeitwerk::Loader.new + push_dir("lib")` 装载全部应用代码：`lib/em_tools/core/...` ↔ `EmTools::Core::...`，`lib/em_tools/plugins/...` ↔ `EmTools::Plugins::...`，`lib/em_tools/clients/...` ↔ `EmTools::Clients::...`。新增文件时只要路径与常量名对应（例如 `lib/em_tools/plugins/amazon_uploadable/pipelines/upload_products_from_es/runner.rb` → `EmTools::Plugins::AmazonUploadable::Pipelines::UploadProductsFromEs::Runner`），不需要手写 `require`。

**可学点**：即使不是 Rails / gem，也可以用 Zeitwerk 管理普通 Ruby 应用；只要保持「文件路径 ↔ 常量名」一致，`bin/` 入口保持薄，只有需要自注册的入口文件（每个 plugin 的 `plugin.rb`）才显式 `require`。

---

## 2. CLI 可维护性：从「巨型 exe」到「注册表 + 命令类」

历史上所有子命令写在一个 `exe/em-tools` 里，随着选项增多会难以阅读与测试。当前做法：

- `EmTools::Core::Cli::App`：只负责 CLI 生命周期（help / 参数校验 / dispatch）。
- `EmTools::Core::Cli::CommandRegistry`：集中内置命令定义，启动后一次性收集插件贡献的命令并缓存。
- `EmTools::Core::Cli::HelpRenderer`：从 registry 渲染 help，不把 UI 逻辑混进 runtime。
- `EmTools::Core::Cli::Support`：共享的 `ELASTICSEARCH_URL` 检查、YAML 安全加载、关键词文件读取。
- `EmTools::Core::Cli::Commands::*` 与 `EmTools::Plugins::<Plugin>::Cli::*`：每个子命令一个类，内部仍用标准库 `OptionParser`（无额外 Thor 依赖）。

**可学点**：**可执行文件保持极薄**（`require 'em_tools'` + `App.start`），业务与 CLI 解析放在 `lib/`，便于单元测试与 RuboCop 分目录排除策略（见 `.rubocop.yml` 中对 `cli/commands/**` 的合理放宽）。

---

## 3. 组合根（Composition Root）与「边界诚实」

Python 里 `amz_upload_products_from_es.py` 做了典型胶水代码：`init_db`、`AmzOfferService`、`PriceCalculator`、`get_product_service()`，再交给 `AmzUploadableProductsFormatter.run()`。Ruby 侧用 `EmTools::Plugins::AmazonUploadable::Pipelines::UploadProductsFromEs::Runner` 扮演**组合根**：

- 已实现：与 Python 一致的 **价格规则默认值与 YAML 合并**（`EmTools::Plugins::AmazonUploadable::Transforms::PriceRules`），以及 **Elasticsearch ASIN 流**（复用 `UploadableProductFilter` / PIT 扫描）。
- 未迁入本 gem、在 `Runner#describe` 的 `implemented` 字段里标为 `false`：product 服务、offer 服务、价格管线、规则引擎、写本地统计文件等。

**可学点**：跨语言迁移时，与其假装功能对等，不如在 API 与 JSON manifest（`--dry-run`）里**明确标出能力边界**，方便后续按阶段补齐而不破坏入口形状。

---

## 4. 与 Python 对齐的配置键

- ASIN 流：`AsinStreamOptions` / YAML 块 `amz.uploadable_filter.asin_stream` 等与 em-tasks 侧一致。
- 价格规则：支持扁平键 `price.rules.amz_<marketplace>` 或嵌套 `price.rules.amz_<marketplace>`（见 `examples/config/amz_celery_compat.example.yml`）。

**可学点**：配置层尽量**沿用已有键名**，降低运维与文档的心智负担；解析逻辑集中在小类中便于 RSpec 覆盖。

---

## 5. Elasticsearch 客户端抽象

`EmTools::Clients::ElasticsearchClient` 封装 PIT + `search_after` 式迭代（`iterate_query` / `iterate_all`），命令层只关心「查什么、对每条 hit 做什么」。

**可学点**：把 HTTP/ES 细节收进单一客户端，上层用领域对象（如 `UploadableProductFilter#asin_query`）描述查询，便于替换测试替身或升级 ES 版本。

---

## 6. 安全加载 YAML

CLI 使用 `YAML.safe_load` 并限制 `permitted_classes`，避免任意对象反序列化风险。

**可学点**：对外部路径读入的配置一律走安全加载；需要 ERB 的环境（如 `Config::Gcs`）与纯静态 YAML 分开处理。

---

## 7. RuboCop 与「CLI 例外」

OptionParser 块天然偏长。项目在 `.rubocop.yml` 里对 `lib/em_tools/core/cli/commands/**/*` 与 `lib/em_tools/plugins/*/cli/**/*` 排除了部分 Metrics 规则，避免为凑行数而把每个 flag 拆成过度抽象。

**可学点**：静态分析规则应**服务可读性**；对机械性 CLI 代码采用目录级排除，比在业务核心类上滥用 `rubocop:disable` 更健康。

---

## 8. 测试策略

- `PriceRules`、`UploadProductsFromEs::Runner` 的 `describe` 行为用 RSpec 快速锁定。
- 与黑名单引擎等依赖 Rust 扩展或外部 API 的 spec 可能因环境不同而失败；新加 spec 应优先保持**纯 Ruby、无外部服务**。

**可学点**：为迁移/配置类写小而快的例子，比一上来端到端测整个 ES 集群更可持续。

---

## 相关命令速查

| 命令 | 作用 |
|------|------|
| `em-tools amz-uploadable:filter` | ASIN 流 + 完整 stream 相关 CLI 选项（与 em-tasks 对齐最多）。 |
| `em-tools amz-uploadable:upload-from-es` | 与 Celery 脚本一致的 `-m` / `-i` / `-t` 入口 + 价格规则 YAML + ASIN 流；`--dry-run` 输出 manifest JSON。 |

更多用法见各命令类内 `OptionParser` 的 `--help` 文案。

---

## 延伸阅读（仓库外）

- [Zeitwerk README](https://github.com/fxn/zeitwerk)
- [Ruby OptionParser](https://docs.ruby-lang.org/en/master/OptionParser.html)

---

## 与仓库内其它文档的关系

- **`docs/ARCHITECTURE.md`**：mono repo 分层、目录约定、如何加功能，以及与 `EmTools::Core::Pipeline` 的配合方式。
- **`docs/DDD_AND_UBIQUITOUS_LANGUAGE.md`**：DDD 视角下的通用语言、限界上下文，以及 `EmTools::Plugins::AmazonLowestOffer::Queries::*` 业务 façade 的用法。
