# Prepare upload — marketplace upload NDJSON

Commands that **read product documents from Elasticsearch** (and sometimes
`em_inventory`), apply marketplace rules (blacklist, price, validation, skip
already-uploaded SKUs), and **write upload-ready NDJSON** for downstream
storefront / Celery pipelines.

This doc is the dedicated reference for that workflow. For inventory sync,
ES dumps, coverage snapshots, and the full command index, see
[`CLI.md`](CLI.md). For `.env` / `settings.yml`, see
[`CONFIGURATION.md`](CONFIGURATION.md).

---

## Quick reference

| Channel | Command | Default output |
|---|---|---|
| Amazon (ASIN stream) | `amazon products upload-from-es` | stdout or `-o` file |
| Amazon (filter only) | `amazon products filter` | stdout or `--to-es` index |
| Amazon (feed rows) | `amazon products build-feed` | `-o` JSONL and/or `--sink-index` |
| Amazon (local file) | `amazon products format-file PATH` | shaped records |
| Lotteon | `lotteon products build-upload-payload` | `tmp/lotteon_upload_payload.ndjson` |
| Oliveyoung | `oliveyoung products build-upload` | `tmp/oliveyoung_store_upload.ndjson` |
| Lazada | `lazada products build-upload -m th\|my` | `tmp/lazada_<m>_upload.ndjson` |
| SSG | `ssg products export` | stdout NDJSON (raw ES shape; no upload formatter) |

All commands load `.env` when run via `bundle exec bin/em-tools …`.

---

## Typical flow

```mermaid
flowchart LR
  Inv[em_inventory<br/>inventory sync] --> ES[(Product ES indices)]
  Trans[es translate-titles<br/>optional] --> ES
  ES --> Prep[prepare-upload CLI]
  Bl[blacklist download] --> Prep
  Prep --> NDJSON[Upload NDJSON / ASIN list]
  NDJSON --> Down[Storefront / Celery / manual upload]
```

1. **Inventory** in `em_inventory` (see [`INVENTORY_SYNC.md`](INVENTORY_SYNC.md)) so formatters can skip SKUs already on Spree.
2. **Product index** populated (scrapers / indexers outside this doc).
3. Optional **`es translate-titles`** → sidecar index; merge with `--translation-index` on Lotteon / Oliveyoung / Lazada.
4. Optional **`blacklist download`** — keyword policy uses the admin API unless you pass `--keywords-path`.
5. Run the marketplace **build-upload** (or Amazon upload pipeline) command.
6. Feed the resulting file to your upload worker.

---

## Shared options (storefront channels)

Lotteon, Oliveyoung, and Lazada share several behaviors:

| Flag / setting | Purpose |
|---|---|
| `--keyword-filter` / `--no-keyword-filter` | Prohibited keywords on title + brand (default: on for OY/Lotteon; Lazada uses profile + force flags) |
| `--keywords-path` | Local keyword list instead of API |
| `--blocked-output` | NDJSON side file for rejected rows |
| `--inventory-source` | `em_inventory` feed key for “already uploaded” skip (defaults: `lotteon`, `oliveyoung`, or Lazada profile `lazadacoth` / `lazadamys`) |
| `--translation-index` | `mget` translation docs (`_id` = SHA256(`source` + NUL + `source_product_id`)); merge `title_en` before formatting |
| `--no-validate-for-upload` / `--no-validate-payload` | Skip `EmProduct::StandardProduct` check |

Translation index workflow: [`CLI.md` — `es translate-titles`](CLI.md#es-translate-titles).

---

## Amazon (`amazon products …`)

Ruby port of the em-celery **upload-from-ES** path. Uses the `:amazon` plugin uploadable scope.

### `amazon products upload-from-es`

Stream eligible ASINs from the Amazon ASIN index (rule engine + stream options), write ASINs to stdout or a file. Celery-compat YAML via `--config`.

```bash
ELASTICSEARCH_URL='http://…' \
bundle exec bin/em-tools amazon products upload-from-es -m de

bundle exec bin/em-tools amazon products upload-from-es -m de --dry-run
bundle exec bin/em-tools amazon products upload-from-es -m de -o tmp/amz_de_asins.txt \
  --config examples/config/amz_celery_compat.example.yml
```

| Option | Purpose |
|---|---|
| `-m` / `--marketplace` | Marketplace code (default `us`) |
| `-t` / `--ttl` | Offer TTL days (informational; default `30`) |
| `--config` | YAML merged into stream + price rules |
| `-o` / `--output` | Write ASINs to file instead of stdout |
| `--dry-run` | Print resolved manifest JSON and exit |
| `--max-asins` | Cap rows (testing) |

### `amazon products filter`

Phase-1 ASIN filter only: stream from `amz_asins_<mp>`, print or bulk-index to `amz_uploadable_asins_<mp>`.

```bash
bundle exec bin/em-tools amazon products filter -m de --asin-since-days 1
bundle exec bin/em-tools amazon products filter -m de --to-es --refresh
```

### `amazon products build-feed`

Build **feed rows** (not just ASINs) from ES or file seeds; JSONL file and/or ES sink.

```bash
bundle exec bin/em-tools amazon products build-feed -m de --dry-run
bundle exec bin/em-tools amazon products build-feed -m de -o tmp/feed.de.ndjson
```

### `amazon products format-file PRODUCTS_PATH`

Format a local product file into the upload pipeline input shape.

---

## Lotteon

### `lotteon products build-upload-payload`

Reads Lotteon products from ES, optional keyword policy, then **format → refine** pipeline (YAML + Ruby). Default formatter: `ProductExportFormatter`.

```bash
ELASTICSEARCH_URL='http://…' \
bundle exec bin/em-tools lotteon products build-upload-payload \
  -o tmp/lotteon_upload_payload.ndjson

bundle exec bin/em-tools lotteon products build-upload-payload \
  --pipeline examples/config/lotteon_upload_pipeline.example.yml \
  --translation-index em_title_translations
```

| Option | Purpose |
|---|---|
| `--pipeline` | YAML exclusions + transforms (see example file) |
| `-o` / `--output` | Upload NDJSON path |
| `--no-keyword-filter` / `--no-validate-payload` | Disable checks |
| `--inventory-source` | Default `lotteon` |
| `--translation-index` | Merge `title_en` before transforms |

Pipeline order is documented in `examples/config/lotteon_upload_pipeline.example.yml` and
{EmTools::Plugins::Lotteon::Pipeline::Registry}.

Raw ES NDJSON without upload shaping: `lotteon products export`.

---

## Oliveyoung

### `oliveyoung products build-upload`

Download Oliveyoung products (`source=oliveyoung`), apply Spree dedupe, `StandardProduct` check, price transform, keyword policy → storefront-upload NDJSON.

```bash
ELASTICSEARCH_URL='http://…' \
bundle exec bin/em-tools oliveyoung products build-upload \
  -o tmp/oy_upload.ndjson

bundle exec bin/em-tools oliveyoung products build-upload \
  --translation-index em_title_translations \
  --no-keyword-filter
```

| Option | Purpose |
|---|---|
| `-o` / `--output` | Default `tmp/oliveyoung_store_upload.ndjson` |
| `-s` / `--source` | ES source filter (default `oliveyoung`) |
| `--inventory-source` | Default `oliveyoung` |
| `--no-validate-for-upload` | Skip StandardProduct validation |

Raw export: `oliveyoung products export` (same index, no upload formatter).

---

## Lazada (Thailand / Malaysia)

Marketplace code **`-m th`** or **`-m my`** (or custom keys under `lazada_marketplaces` in `config/settings.yml`).

### Configuration

- **`exporters.<exporter_key>`** — ES URL + index (`lazada_th_products` → `user1_lazadacoth_products`, etc.).
- **`lazada_marketplaces.<code>`** — `inventory_source` (default `lazadacoth` / `lazadamys`), `display_source`, `sku_prefix`, `price_rules`, `formatter_filters`, `products_query`, `keyword_filter_default`, `translate_by_default`, `translation_index`, `extra_es_filters`, …

See {EmTools::Plugins::Lazada::MarketplaceProfile}.

Ensure `inventory_sync` has loaded the matching inventory CSV into `em_inventory` with the same `source` / `inventory_feed` as `inventory_source`.

### `lazada products build-upload`

```bash
bundle exec bin/em-tools lazada products build-upload -m th \
  -u 'http://user:pass@host:9200' \
  -o tmp/lazada_th_upload.ndjson

bundle exec bin/em-tools lazada products build-upload -m my --no-keyword-filter
bundle exec bin/em-tools lazada products build-upload -m th \
  --force-translate --translation-index em_title_translations
```

| Option | Purpose |
|---|---|
| `-m` / `--marketplace` | `th`, `my`, … (default `th`) |
| `-u` / `--url` | ES base URL override |
| `--no-keyword-filter` / `--force-keyword-filter` | Override YAML `keyword_filter_default` |
| `--no-translate` / `--force-translate` | Translation merge toggles |
| `--inventory-source` | Override profile default |

Export with upload filters but without final upload file layout: `lazada products export --for-upload`.

---

## SSG

`ssg products export` streams the SSG product index as **raw NDJSON** (no upload formatter in em-tools today). Use when you only need an ES extract; upload shaping may happen outside this repo.

```bash
bundle exec bin/em-tools ssg products export -o tmp/ssg_products.ndjson
```

---

## Storefront import (local NDJSON)

`storefront import-products INPUT_PATH` filters **local** NDJSON feeds through the rule engine (not an ES → upload-NDJSON builder). See [`CLI.md` — Storefront](CLI.md#storefront-pluginsstorefront).

---

## Related CLI (not upload NDJSON)

These commands support catalog ops but are not “prepare upload” outputs:

| Command | Role |
|---|---|
| `amazon products export-by-top-category` | ASIN lists per `top_category` |
| `amazon products top-category-stats` | Category counts |
| `google-ads catalog missing-product-ids` | Set diff vs `em_inventory` |

Full flags and exit codes: [`CLI.md`](CLI.md).
