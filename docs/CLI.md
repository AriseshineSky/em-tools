# em-tools CLI reference

`bin/em-tools` is the **only** operational entrypoint. The CLI is a hierarchical
subcommand tree built on [dry-cli](https://dry-rb.org/gems/dry-cli/), shaped
like `kubectl` / `git`:

```
em-tools <area> <action> [options] [arguments]
```

Every command:

- Loads `.env` automatically (via `dotenv`) when invoked through `bundle exec`.
- Wraps long-running work in {EmTools::Core::Cli::Runner}, which turns
  {EmTools::Core::Errors::ConfigurationError} and
  {EmTools::Core::Errors::EmptyResultError} into a one-line `error: <msg>` and
  `exit 1`.
- Prints a one-line `result.summary` on success.
- Supports `-h` / `--help` for per-command help.

## Help / discovery

```bash
bundle exec bin/em-tools                                # top-level command tree
bundle exec bin/em-tools <area>                          # subtree (e.g. inventory)
bundle exec bin/em-tools <area> <action> --help         # per-command help
```

`./bin/em-tools …` (without `bundle exec`) also works — the script calls
`bundler/setup` itself. For unattended / recurring invocation (cron, systemd
timers), see [`../schedule/README.md`](../schedule/README.md).

---

## Command index

```mermaid
flowchart LR
    Root[em-tools] --> Core
    Root --> Plugins

    subgraph Core
        Dump[dump INDEX]
        Es[es]
        Inv[inventory]
        Gcs[gcs]
        Bl[blacklist]
    end

    Es --> EsDump[es dump-index]
    Es --> EsDl[es download-product]
    Es --> EsTr[es translate-titles]
    Inv --> InvSync[inventory sync]
    Inv --> InvSyncOne[inventory sync-from-gcs]
    Gcs --> GcsSeeds[gcs download-seeds]
    Bl --> BlDl[blacklist download]

    subgraph Plugins
        Amz[amazon]
        Sf[storefront]
        Ebay[ebay]
        Gads[google-ads]
        Ssg[ssg]
        Lot[lotteon]
        Laz[lazada]
    end

    Amz --> AmzF[amazon products filter]
    Amz --> AmzU[amazon products upload-from-es]
    Amz --> AmzFmt[amazon products format-file]
    Amz --> AmzA[amazon products index-asins]
    Sf --> SfImp[storefront import-products]
    Sf --> SfSync[storefront inventory sync]
    Sf --> SfUnp[storefront unpublish-candidates]
    Ebay --> EbayPub[ebay listings publish-snapshot]
    Gads --> GadsCat[gads catalog sync]
    Gads --> GadsCatOne[gads catalog sync-from-gcs]
    Amz --> AloPub[amazon coverage publish-snapshot]
    Amz --> AloDl[amazon coverage download-and-publish]
    Ssg --> SsgEx[ssg products export]
    Lot --> LotEx[lotteon products export]
    Lot --> LotUp[lotteon products build-upload-payload]
    Laz --> LazEx[lazada products export]
    Laz --> LazBu[lazada products build-upload]
```

| Path | Class |
|---|---|
| `dump INDEX` | `Core::Cli::Commands::Dump` |
| `es dump-index` | `Core::Cli::Commands::EsDumpIndex` |
| `es download-product` | `Core::Cli::Commands::EsDownloadProduct` |
| `es translate-titles` | `Core::Cli::Commands::EsTranslateTitles` |
| `inventory sync [CONFIG_PATH]` | `Core::Cli::Commands::InventorySync` |
| `inventory sync-from-gcs [GS_URI]` | `Core::Cli::Commands::InventorySyncFromGcs` |
| `google-ads catalog sync [CONFIG_PATH]` | `Plugins::GoogleAds::Cli::CatalogSync` |
| `google-ads catalog sync-from-gcs [GS_URI]` | `Plugins::GoogleAds::Cli::CatalogSyncFromGcs` |
| `gcs download-seeds` | `Core::Cli::Commands::GcsDownloadSeeds` |
| `blacklist download` | `Core::Cli::Commands::BlacklistDownload` |
| `amazon products filter` | `Plugins::Amazon::Uploadable::Cli::UploadableProductFilter` |
| `amazon products upload-from-es` | `Plugins::Amazon::Uploadable::Cli::AmzUploadProductsFromEs` |
| `amazon products format-file PRODUCTS_PATH` | `Plugins::Amazon::Uploadable::Cli::AmzUploadableProductsFormatterFromFile` |
| `amazon products index-asins` | `Plugins::Amazon::Uploadable::Cli::AsinProductsToEs` |
| `amazon products build-feed` | `Plugins::Amazon::Uploadable::Cli::BuildUploadableFeed` |
| `storefront import-products INPUT_PATH` | `Plugins::Storefront::Cli::ImportProducts` |
| `storefront inventory sync` | `Plugins::Storefront::Cli::SyncInventory` |
| `storefront unpublish-candidates` | `Plugins::Storefront::Cli::UnpublishCandidates` |
| `ebay listings publish-snapshot [MARKETPLACE]` | `Plugins::Ebay::Cli::PublishSnapshot` |
| `amazon coverage publish-snapshot [MARKETPLACES...]` | `Plugins::Amazon::LowestOffer::Cli::PublishSnapshot` |
| `amazon coverage download-and-publish` | `Plugins::Amazon::LowestOffer::Cli::DownloadAndPublish` |
| `ssg products export` | `Plugins::Ssg::Cli::ExportProducts` |
| `lotteon products export` | `Plugins::Lotteon::Cli::ExportProducts` |
| `lotteon products build-upload-payload` | `Plugins::Lotteon::Cli::BuildUploadPayload` |
| `lazada products export` | `Plugins::Lazada::Cli::ExportProducts` |
| `lazada products build-upload` | `Plugins::Lazada::Cli::BuildUpload` |

---

## Elasticsearch & extracts

### `dump INDEX`

Stream every document of an ES index as NDJSON. Cluster selection (explicit
URL, primary, or data) is delegated to `EmTools::Core::Config.elasticsearch_client`.

```bash
bundle exec bin/em-tools dump ssg_products > ssg_products.ndjson
bundle exec bin/em-tools dump user1_lotteon_products --data -o tmp/lotteon.ndjson
bundle exec bin/em-tools dump user1_kr_products -u 'http://user:pw@host:9200'
```

### `es dump-index`

Env-driven dump from the **primary** cluster (`ELASTICSEARCH_URL`) to a local
NDJSON file using the `ES_DUMP_*` env vars.

```bash
ES_DUMP_INDEX=user1_lotteon_products \
ES_DUMP_OUTPUT=tmp/lotteon.ndjson \
bundle exec bin/em-tools es dump-index
```

Required env: `ELASTICSEARCH_URL`, `ES_DUMP_INDEX`. Optional: `ES_DUMP_OUTPUT`
(default `tmp/<index>.ndjson`), `ES_DUMP_BATCH_SIZE` (default `1000`).

### `es download-product`

Like `es dump-index`, but reads from the **data cluster**
(`DATA_ELASTICSEARCH_URL`) and applies the keyword **blacklist policy** by default.

```bash
DATA_ELASTICSEARCH_URL='http://user:pw@host:9200' \
ES_DUMP_INDEX=user1_kr_products \
ES_DUMP_OUTPUT=tmp/kr_products.ndjson \
bundle exec bin/em-tools es download-product
```

For each hit, `EmTools::Core::Blacklist` selects the `product_download` rule
from `config/blacklist/source_rules.yml`. The current rule uses the
`title_brand` strategy: build the lowercased text `"<title> <brand>"` and run
it through an Aho-Corasick automaton seeded with the keywords returned by
`blacklist download`. Blacklisted hits are **not** written to the main NDJSON;
instead, one record per rejection is appended to `<output>.blocked.ndjson`
with the doc `_id`, title, brand, and matched keywords.

| Flag | Purpose |
|---|---|
| `--no-blacklist-filter` | Disable filtering entirely (raw dump). |
| `--title-field FIELD` | Source field for product title (default `title`). |
| `--brand-field FIELD` | Source field for product brand (default `brand`). |
| `--blocked-output PATH` | Override the blocked-products side-file path. |

### `es translate-titles`

Scans an index with a point-in-time `match_all` search, reads `--source-field`
(default `title`), and when the value **looks Korean or Japanese** (Hangul /
kana / CJK-without-Hangul heuristic; not a full language detector), sends it
through `EmTools::Core::Translation::BudgetedTranslator`.

**Where results go**

1. **Sidecar translation index** (optional): pass `--translation-index NAME`. Each
   document uses `_id = SHA256(source NUL source_product_id)` (see
   `EmTools::Core::Translation::DocId`) and stores `source`, `source_product_id`,
   original `title`, `title_en`, `target_lang`, `updated_at`, and optional
   `product_index`. Create the index beforehand (dynamic mapping is fine for
   prototyping).
2. **Product index** (optional): partial-updates `--target-field` (default
   `title_en`) on the scanned index. If you only use a translation index, omit
   `--also-update-product` (default). Add `--also-update-product` to also patch
   the product document.

Requires Google Cloud Translation v2 credentials (ADC or `TRANSLATE_KEY` /
`GOOGLE_CLOUD_KEY`) and a **positive** `EM_TRANSLATE_MAX_CHARS` (or YAML
`translate.max_billable_chars`). See `.env.example` and
`examples/config/settings.example.yml`.

```bash
ELASTICSEARCH_URL='http://localhost:9200' \
EM_TRANSLATE_MAX_CHARS=500000 \
bundle exec bin/em-tools es translate-titles user1_oliveyoung_products \
  --translation-index em_title_translations --dry-run

bundle exec bin/em-tools es translate-titles user1_oliveyoung_products \
  --translation-index em_title_translations --also-update-product
```

**Export:** Oliveyoung and Lotteon CLIs accept `--translation-index` (and related
flags) to `mget` each row’s translation by the same `_id` rule and merge
`title_en` before upload shaping / NDJSON conversion.

| Flag | Purpose |
|---|---|
| `--source-field FIELD` | Field to read (one dot level supported, e.g. `meta.title`; default `title`). |
| `--target-field FIELD` | Product index partial-update field (default `title_en`; used with `--also-update-product`). |
| `--langs CODES` | Comma list; title must pass heuristic for one code (default `ko,ja`). |
| `--to LANG` | Google target language (default `en`). |
| `--source-lang LANG` | Optional fixed source language; omit for auto-detect per string. |
| `-b` / `--batch-size` | PIT page size (default `500`). |
| `--bulk-size` | Bulk actions per HTTP request (default `50`). |
| `-u` / `--url` | Elasticsearch base URL override. |
| `--data` | Use `DATA_ELASTICSEARCH_URL` when set. |
| `--dry-run` | Count and translate in memory only; no bulk writes. |
| `--overwrite` | When updating the **product** index, skip the usual skip-if-target-nonempty rule. |
| `--translation-index NAME` | Bulk-**index** translation rows into this sidecar index. |
| `--source-key-field FIELD` | Product field for `source` stored in translation docs / doc id (default `source`). |
| `--source-product-id-field FIELD` | Product field for id within source (default `source_product_id`). |
| `--also-update-product` | When using `--translation-index`, also partial-update the product `--target-field`. |

---

## Inventory & object storage

### `inventory sync [CONFIG_PATH]`

Reads `inventory_sync.sources` from the merged settings YAML (or the file at
the given path) and streams every GCS CSV into the inventory ES index
(`em_inventory` by default).

Cluster precedence (highest wins):

1. per-source `cluster:` in YAML
2. `inventory_sync.cluster:` section default
3. `--data` flag (defaults sources without `cluster:` to `DATA_ELASTICSEARCH_URL`)
4. `ELASTICSEARCH_URL`

Required env: `ELASTICSEARCH_URL`. Optional: `GCS_SERVICE_ACCOUNT_PATH`,
`INVENTORY_INDEX`, `INVENTORY_DROP_FIELDS`.

### `inventory sync-from-gcs [GS_URI]`

Single-source debug variant. The URI can come from the CLI argument,
`INVENTORY_GS_URI`, or `INVENTORY_GCS_BUCKET` + `INVENTORY_GCS_OBJECT`.

Optional env: `INVENTORY_INDEX`, `INVENTORY_REFRESH=1`,
`INVENTORY_PRUNE_OBSOLETE=1`, `INVENTORY_FEED_ID`, `INVENTORY_DROP_FIELDS`
(comma-separated; e.g. `"handle,variants"`).

### `google-ads catalog sync [CONFIG_PATH]`

Same mechanics as `inventory sync`, but targets the **Google Ads product catalog**
(SKUs shown in ads), not cross-channel operational inventory. Reads
`google_ads_catalog_sync.sources` from settings YAML (default index:
`google_ads_products`). Documents use `google_ads_feed` (not `inventory_feed`)
for prune semantics.

Required env: `ELASTICSEARCH_URL`. Optional: `GOOGLE_ADS_CATALOG_INDEX`,
`GOOGLE_ADS_CATALOG_*` (see `.env.example`).

```bash
bundle exec bin/em-tools google-ads catalog sync
bundle exec bin/em-tools google-ads catalog sync-from-gcs gs://em-bucket/google-ads-us.csv --data
```

**Feed file formats** (set `format` in YAML):

| `format` | File shape | `_id` |
|---|---|---|
| `tab_json` | `<ignored>\\t{json}` per line (Python `json.loads` after first tab) | JSON `product_id` |
| `asin_list` | one ASIN per line | the ASIN string |

Example `tab_json` source:

```yaml
- uri: gs://em-bucket/em-analytics/sources/AMZ_DE.txt
  format: tab_json
  source: AMZ_DE
```

### `google-ads catalog missing-product-ids`

Exports `source_product_id` values that exist in `em_inventory` but are absent from
`google_ads_products` for the same `source` (set difference).

```bash
ELASTICSEARCH_URL='http://34.44.148.50' \
bundle exec bin/em-tools google-ads catalog missing-product-ids \
  --source AMZ_DE \
  -o tmp/amz_de_missing_from_google_ads.txt
```

| Flag | Purpose |
|---|---|
| `--source` | Source key (e.g. `AMZ_DE`; matches case variants) |
| `-o` / `--output` | Local output path |
| `--inventory-index` | Default `em_inventory` |
| `--catalog-index` | Default `google_ads_products` |
| `-u` / `--url` | ES URL override |

### `google-ads catalog asin-categories`

Reads a local ASIN list (e.g. from `catalog missing-product-ids`), batch **mget** from
`amz_products_api_<marketplace>_v2` (`_id` = ASIN), and writes the **first** `categories[]`
entry (`cat_id`, `cat_name`) per row to a TSV file.

```bash
bundle exec bin/em-tools google-ads catalog asin-categories \
  -i tmp/amz_de_missing_from_google_ads.txt \
  -o tmp/amz_de_asin_categories.tsv \
  -m de
```

Output columns: `asin`, `cat_id`, `cat_name`, `status` (`ok` / `not_found` / `no_category`).

### `gcs download-seeds`

Pulls Amazon lowest-offer seed files (`AMZ_<MP>.txt`) from
`gs://$GCS_BUCKET/$GCS_SEEDS_PREFIX/` into `./tmp/amz_<mp>.txt`. Required
env: `GCS_SERVICE_ACCOUNT_PATH` (or default GCS credentials).

---

## Reference data

### `blacklist download`

Downloads the keyword blacklist from the Everymarket admin API. Used to refresh
the local keyword set that the storefront / Amazon importers feed into
`EmTools::Core::Blacklist` (Aho-Corasick).

```bash
# Print parsed keywords to stdout, one per line
bundle exec bin/em-tools blacklist download

# Persist to a file
bundle exec bin/em-tools blacklist download -o tmp/blacklist.txt

# Inspect the raw API response (useful when the schema changes)
bundle exec bin/em-tools blacklist download --raw -o tmp/blacklist.json
```

Required env: `BLACKLIST_API_ENDPOINT`, `BLACKLIST_API_PATH`,
`BLACKLIST_API_TOKEN`. The loader is
tolerant of legacy `{"blacklist_keywords":[{"keywords":[...]}]}` payloads as
well as flatter `{"keywords":[...]}` and bare-array responses, so a
server-side schema flip will not silently produce an empty list.

---

## Plugin commands

The following commands are **plugin-registered**; their availability depends
on the plugin being loaded (which it always is, since
`lib/em_tools.rb` eagerly loads every `plugins/*/plugin.rb`).

### Amazon uploadable (`plugins/amazon/uploadable/`)

| Command | What it does |
|---|---|
| `amazon products filter` | Filter ASINs from one ES index against the rule engine and write the eligible-for-upload list. |
| `amazon products upload-from-es` | Read filtered products from ES and run the Amazon upload pipeline. |
| `amazon products format-file PRODUCTS_PATH` | Format a local file into the upload pipeline's input format. |
| `amazon products build-feed` | Build final uploadable feed rows from an ASIN source into configured sinks. |
| `amazon products export-by-top-category` | Export ASINs from `amz_products_api_<mp>_v2` into one file per `top_category`. |
| `amazon products top-category-stats` | Export all `top_category` values and document counts (TSV + JSON). |

```bash
ELASTICSEARCH_URL='http://34.44.148.50' \
bundle exec bin/em-tools amazon products top-category-stats \
  -m de -o tmp/amz_de_top_category_counts.tsv

bundle exec bin/em-tools amazon products export-by-top-category \
  -m de -o tmp/amz_de_by_top_category
```

`top-category-stats` writes `top_category` + `doc_count` (fast aggregation). Optional `counts.json` summary.

`export-by-top-category` writes `tmp/amz_de_by_top_category/<top_category>.txt` (one ASIN per line) and `manifest.json`.
Use `--category-from categories_first` to group by `categories[0].cat_name` instead of `top_category`.

### Amazon lowest-offer (`plugins/amazon/lowest_offer/`)

| Command | What it does |
|---|---|
| `amazon coverage publish-snapshot [MARKETPLACES...]` | Publish lowest-offer coverage snapshots (one row per marketplace). |
| `amazon coverage download-and-publish` | Composite: `gcs download-seeds` then `coverage publish-snapshot`. |

### eBay (`plugins/ebay/`)

| Command | What it does |
|---|---|
| `ebay listings publish-snapshot [MARKETPLACE]` | eBay listings coverage snapshot (one row per marketplace). |

### Storefront (`plugins/storefront/`)

| Command | What it does |
|---|---|
| `storefront import-products INPUT_PATH` | Filter local NDJSON product feeds against the rule engine. |
| `storefront inventory sync` | Download per-source inventory CSVs from Spree and bulk-index into ES. |
| `storefront unpublish-candidates` | Iterate ES inventory, run rules, write delisting candidates to `em_products_to_unpublish`. |

### SSG / Lotteon (`plugins/ssg/`, `plugins/lotteon/`)

| Command | What it does |
|---|---|
| `ssg products export` | Stream SSG products from Elasticsearch as NDJSON. |
| `lotteon products export` | Stream Lotteon products from Elasticsearch as NDJSON. |
| `lotteon products build-upload-payload` | Build upload NDJSON; optional `--pipeline` YAML composes **exclusions** and **transforms** (format stage — `format:` + `lotteon_upload_format` — then **refine**: other `transforms:` rows, `refine:`, Ruby `transforms:`). See `examples/config/lotteon_upload_pipeline.example.yml` and {EmTools::Plugins::Lotteon::Pipeline::Registry}. |

### Lazada (`plugins/lazada/` — Thailand / Malaysia)

Marketplace is selected with **`-m th`** or **`-m my`** (or any key you add under `lazada_marketplaces` in settings). Each code resolves:

- **`exporters.<exporter_key>`** — ES cluster (`ELASTICSEARCH_URL` / cluster name) + **index name** (`lazada_th_products` → `user1_lazadacoth_products`, `lazada_my_products` → placeholder index; edit YAML).
- **`lazada_marketplaces.<code>`** — optional overrides: `inventory_source`, `display_source`, `sku_prefix`, `price_rules`, `formatter_filters` (toggle skip multi-variant / options / uploaded), `products_query` (`source_field`, `source_value`), `extra_es_filters` (extra ES `bool.filter` clauses), `keyword_filter_default`, `translate_by_default`, `translation_index`, `translation_elasticsearch_url`, `keyword_rules_source`, etc. Defaults live in {EmTools::Plugins::Lazada::MarketplaceProfile}.

Keyword policy: YAML **`keyword_filter_default`** applies when neither **`--force-keyword-filter`** nor **`--no-keyword-filter`** is passed. Translation: merge `title_en` when an index is configured **and** (`translate_by_default` **or** `--translation-index …` **or** `--force-translate`), unless **`--no-translate`**.

| Command | What it does |
|---|---|
| `lazada products export` | NDJSON stream; `-m`; `--for-upload` applies marketplace formatter + filters; `-u` overrides ES URL. |
| `lazada products build-upload` | Upload NDJSON (`tmp/lazada_<m>_upload.ndjson` by default). |

```bash
bundle exec bin/em-tools lazada products build-upload -m th -u 'http://user:pass@host:9200' -o tmp/th.ndjson
bundle exec bin/em-tools lazada products build-upload -m my --no-keyword-filter
bundle exec bin/em-tools lazada products export -m my --force-translate --translation-index em_title_translations_my
```

---

## Exit codes

| Exit code | When | Source |
|---|---|---|
| `0` | Success. `result.summary` printed if available. | normal return |
| `1` | Configuration / empty-result error. Single-line `error: <msg>` printed. | `Cli::Runner` catches `EmTools::Error` subclasses |
| `1` | Argument error (missing required argument, unknown option). | dry-cli built-in |
| anything else | Unexpected `StandardError` (real bug). | propagated, full stacktrace |

To call em-tools from another Ruby script in the same checkout, rescue the
top-level base class:

```ruby
begin
  EmTools::Plugins::Amazon::LowestOffer::Pipelines::PublishSnapshot.new.run!
rescue EmTools::Error => e
  warn "em-tools refused: #{e.message}"
end
```
