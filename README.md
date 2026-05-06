# em-tools

**Purpose:** Internal Ruby gem and CLI for **Everymarket** operational tooling: **Elasticsearch** and **Google Cloud Storage** (inventory CSV sync, lowest-offer snapshots), **Amazon listing helpers** (uploadable NDJSON from ASIN files, ASIN streams with price rules), plus blacklist matching, import filters, and NDJSON index dumps.

**目的（中文）：** 本仓库是 `em-tools` Ruby gem：连接 **Elasticsearch** 与 **GCS**（库存同步、最低价快照）；**Amazon 运维**（从 ASIN 列表拉 ES 商品/报价并生成可上架 NDJSON、ASIN 流与价格规则）；以及黑名单、导入过滤、索引 NDJSON 导出等。

---

## What is in this project

| Area | Role |
|------|------|
| **`Em::Tools::InventorySync`** | Parses inventory CSV (headers normalized to `snake_case`), upserts into ES via a pluggable sink. Uses CSV **`Source`** as **`inventory_feed`** when pruning stale docs. |
| **`Em::Tools::GcsBlobFetcher`** | Service-account auth and download of a single object by `gs://bucket/path`. |
| **`Em::Tools::InventorySyncSources`** | Loads `inventory_sync.sources` from merged settings YAML (or a path you pass to `rake inventory:sync[path]`). |
| **`Em::Tools::ElasticsearchBulkSink`** | Default sink: `bulk`, `refresh`, `delete_by_query` via **`Em::Clients::ElasticsearchClient`**. |
| **Lowest offer** | `LowestOfferListingsCoverageQuery`, `LowestOfferSeedFiles`, `LowestOfferCoverageSnapshot` plus Rake tasks to pull AMZ seeds from GCS and index snapshots. |
| **eBay listings coverage** | `EbayListingsCoverageQuery`, `EbayListingsCoverageSnapshot`, `rake ebay_listings:publish_snapshot` — seed `product_id` list vs one configurable products index (`time` buckets). |
| **`Em::Tools::GcsHelper`** | Bucket-scoped download helpers for seeds and other blobs. |
| **Blacklist / products** | Aho–Corasick–based blacklist engine, SSG product scanner/exporter, product importer. |
| **`exe/em-tools`** | CLI entrypoint: `dump`, `import-products`, `uploadable-product-filter`, `amz-upload-products-from-es`, `amz-uploadable-products-formatter-from-file`, `asin-products-to-es` (see [em-tools CLI](#em-tools-cli) below). |
| **`Em::Tools::Amazon::UploadableProductsFormatterFromFile`** | ASIN file → ES `mget` (product + optional offer index) → one JSON line per ASIN + sidecar files under `~/.em_tasks/amz_<mp>/` (Ruby counterpart to em-celery `amz_uploadable_products_formatter_from_file`). |
| **`Em::Tools::Config` / `SettingsLoader` / `SettingsHydrator`** | One merged YAML (`config/settings.yml` if present, else `examples/config/settings.example.yml`) + `.env`: ES, Redis, blacklist, `sites`, **`gcs`** buckets, **`inventory_sync`** CSV list; optional hydrate into `ENV` at boot. |

Ruby **>= 3.2**. Main gem dependencies: `elasticsearch` ~> 7.17, `google-cloud-storage`, `zeitwerk`, `csv`, `ahocorasick-rust`.

---

## Installation

From a checkout:

```bash
bundle install
```

To use the gem from another app, add to the `Gemfile`:

```ruby
gem 'em-tools', git: 'https://github.com/AriseshineSky/em-tools.git'
```

---

## Configuration files

| File | Purpose |
|------|---------|
| **`examples/config/settings.example.yml`** | Default merged app config in-repo: `elasticsearch`, `redis`, `blacklist_api`, `sites`, **`gcs`** (buckets, optional `service_account_path`), **`inventory_sync`** (`sources`, `index`, `refresh`, `prune_obsolete`). ERB allowed. |
| **`config/settings.yml`** | Optional override (common if `config/` is gitignored): copy or symlink from the example and edit. |
| **`EM_TOOLS_SETTINGS_PATH`** | Point to any YAML file using the same `default` + `APP_ENV` merge shape. |
| **`examples/config/*.example.yml`** | Small CLI-only YAML samples (`amazon_asin_product_pipeline`, `amz_celery_compat`, `amz_uploadable_filter`) passed with `--config`. |
| **`.env` / `.env.example`** | Secrets and machine-local overrides. After `dotenv`, **`Em::Tools::SettingsHydrator`** fills still-blank `ENV` keys from the merged settings file. |

Optional **`.env`** in the repo root is loaded by Rake / `exe/em-tools` when the `dotenv` gem is present.

---

## Environment variables (common)

| Variable | Used by |
|----------|---------|
| **`ELASTICSEARCH_URL`** | ES client URL. Highest priority; otherwise merged settings → `elasticsearch.url`, then **`Em::Tools::Config.elasticsearch_url`**. |
| **`REDIS_URL`** | Optional; **`Em::Tools::Config.redis_url`** reads `ENV` or settings → `redis.url`. |
| **`BLACKLIST_API_*`** | Optional; **`Em::Tools::Config.blacklist_api_*`** merges `ENV` with settings → `blacklist_api`. |
| **`EM_TOOLS_SITE_<NAME>_TOKEN`**, **`_ENDPOINT`**, **`_BASE_URL`** | Override `sites.<name>` from settings (`<NAME>` is uppercased, `-` → `_`). **`Em::Tools::Config.site('acme')`** returns a merged `Hash`. |
| **`EM_TOOLS_SETTINGS_PATH`** | Absolute path to a YAML file instead of the default resolution (`config/settings.yml` or the committed example). |
| **`EM_TOOLS_SKIP_SETTINGS_HYDRATE`** | Set to `1` to skip copying YAML into `ENV` (tests set this in `spec_helper`). |
| **`GCS_SERVICE_ACCOUNT_PATH`** | Path to GCS JSON key. Can also be defaulted from settings `gcs.service_account_path` when hydrated. |
| **`APP_ENV`** | Picks the overlay section merged on top of `default` in the settings YAML (default **`development`**). |

Inventory / one-off sync extras: `INVENTORY_INDEX`, `INVENTORY_REFRESH`, `INVENTORY_GS_URI`, `INVENTORY_GCS_BUCKET`, `INVENTORY_GCS_OBJECT`, `INVENTORY_PRUNE_OBSOLETE`, `INVENTORY_FEED_ID` (see Rake descriptions).

Lowest-offer: see `rake -D lowest_offer:publish_snapshot` for `LOWEST_OFFER_*` variables.

eBay listings coverage: see `rake -D ebay_listings:publish_snapshot` for `EBAY_LISTINGS_COVERAGE_*` (index name, id/time fields, seeds, monitoring snapshot index `MONITORING_EBAY_LISTINGS_SNAPSHOT_INDEX`).

---

## Command line

### Rake (run from repo root)

```bash
cd /path/to/em-tools
bundle install
```

**Inventory: sync all sources from YAML**

Reads `inventory_sync.sources` from the merged settings file (`config/settings.yml` if you have one, otherwise `examples/config/settings.example.yml`), for the current `APP_ENV`, then downloads each `gs://` object and upserts into Elasticsearch.

```bash
export ELASTICSEARCH_URL='http://your-es:9200'
export GCS_SERVICE_ACCOUNT_PATH='/path/to/gcs-sa.json'   # optional if default key file exists

bundle exec rake inventory:sync
```

Use a different config file (path relative to repo root; quote in zsh):

```bash
bundle exec rake 'inventory:sync[tmp/inventory-only.yml]'
```

**Inventory: sync a single GCS object (debug)**

```bash
export ELASTICSEARCH_URL='http://localhost:9200'
bundle exec rake 'inventory:sync_from_gcs[gs://em-bucket/boyner-Inv.csv]'
```

With pruning (removes docs for the same `inventory_feed` / CSV `Source` not written in this run; requires `Source` column or `INVENTORY_FEED_ID`):

```bash
export INVENTORY_PRUNE_OBSOLETE=1
bundle exec rake inventory:sync_from_gcs
```

**GCS: download lowest-offer AMZ seed files**

```bash
export GCS_SERVICE_ACCOUNT_PATH='/path/to/gcs-sa.json'
bundle exec rake gcs:download_seeds
```

**Lowest offer: publish snapshot to Elasticsearch**

```bash
export ELASTICSEARCH_URL='http://localhost:9200'
bundle exec rake lowest_offer:publish_snapshot
```

**Lowest offer: download seeds then publish**

```bash
bundle exec rake lowest_offer:download_and_publish
```

**eBay listings coverage (same time buckets as lowest-offer, configurable ES index)**

Uses seed `ebay_<mp>.txt` (same tab + JSON column 2 as lowest-offer seeds) or `EBAY_LISTINGS_COVERAGE_SEED_FILE`, or `EBAY_LISTINGS_COVERAGE_ID_SOURCE=inventory`. Set `EBAY_LISTINGS_COVERAGE_INDEX` (default `ebay_us_products`). See `rake -D ebay_listings:publish_snapshot` for all `EBAY_LISTINGS_COVERAGE_*` variables.

```bash
export ELASTICSEARCH_URL='http://localhost:9200'
export EBAY_LISTINGS_COVERAGE_INDEX='ebay_us_products'
export EBAY_LISTINGS_COVERAGE_SEED_DIR='tmp'
bundle exec rake 'ebay_listings:publish_snapshot[us]'
```

**Gem packaging**

```bash
bundle exec rake build
bundle exec rake install
```

### em-tools CLI

Run from a checkout as `bundle exec ruby -I lib exe/em-tools …`, or after `bundle exec rake install` as `bundle exec em-tools …`. Load order: **Bundler** → optional **`dotenv`** (`.env`) → **`Em::Tools::SettingsHydrator`** (YAML defaults into blank `ENV` keys) → command.

**Global:** set **`ELASTICSEARCH_URL`** (or `config/settings.yml` + hydrate) for any command that talks to ES. Command-specific help: `bundle exec em-tools COMMAND --help` (e.g. `… dump --help`).

| Command | Summary |
|---------|---------|
| **`dump`** | Stream an ES index to NDJSON (`INDEX` positional argument). |
| **`import-products`** | Read NDJSON products, filter, emit import batch plans. |
| **`uploadable-product-filter`** | Stream Amazon ASINs from ES with stream/query flags (see `--help`). |
| **`amz-upload-products-from-es`** | em-celery–compatible flags: marketplace, optional ASIN index, TTL, YAML price rules (`-m`, `-i`, `-t`, `--config`). |
| **`amz-uploadable-products-formatter-from-file`** | ASIN file → ES `mget` → uploadable listing NDJSON + sidecars (see below). |
| **`asin-products-to-es`** | ASIN index → product `mget` → filters → bulk to a sink ES index. |

#### `amz-uploadable-products-formatter-from-file`

Ruby port of **`em_celery.tools.spree.amz_uploadable_products_formatter_from_file`** (`filter_products`). Reads **one ASIN per line**, loads **`amz_products_api_<mp>_v2`** (override with `--product-index`) and optionally **`lowest_offer_listings_<mp>_new`** (`--offer-index`), merges **price/currency**, writes **NDJSON** to `-o`, and appends **`record_messages.txt`** plus ASIN list files under **`--emitter-dir`** (default `~/.em_tasks/amz_<mp>/`).

**Required flags:** `-s` store code, `-o` output path, **`--so` / `--source`**, **`--sc` / `--source-code`** (Ruby `OptionParser` cannot use Python’s `-so`/`-sc` next to `-s`; use long forms **`--so`** and **`--sc`**). Optional: `-m`, `-e`, `-t`, `--skip-offers` (take price from product doc), `--batch-size`, index overrides.

```bash
export ELASTICSEARCH_URL='http://localhost:9200'
bundle exec ruby -I lib exe/em-tools amz-uploadable-products-formatter-from-file \
  -s MYSTORE -m us -o listings.ndjson \
  --so AMZ_US --sc wholesale \
  asins.txt
```

### Library usage

```ruby
require 'em/tools'

# Elasticsearch URL resolution (ENV, then config/settings.yml):
Em::Tools::Config.elasticsearch_url

# Optional Redis / per-site HTTP settings from YAML + ENV (see Configuration files):
Em::Tools::Config.redis_url
Em::Tools::Config.site('example_partner') # => { "endpoint" => ..., "token" => ... }

# Example: programmatic inventory sync (GCS → temp file → ES) is usually composed from
# Em::Tools::GcsBlobFetcher, Em::Tools::InventorySync, Em::Tools::ElasticsearchBulkSink
```

---

## Development

```bash
bundle exec rspec
bundle exec rubocop
```

Rake task definitions live under **`rakelib/*.rake`** (auto-loaded by Rake). Core library code is under **`lib/em/tools/`** with **`Em::Clients::ElasticsearchClient`** in **`lib/em/clients/`**.

---

## Contributing

Issues and pull requests: [github.com/AriseshineSky/em-tools](https://github.com/AriseshineSky/em-tools).
