# em-tools CLI reference

For **inventory sync** into `em_inventory`, see [`INVENTORY_SYNC.md`](INVENTORY_SYNC.md).
For **upload NDJSON** generation, see [`PREPARE_UPLOAD.md`](PREPARE_UPLOAD.md).
For **Amazon lowest-offer coverage** (ad-report ASINs → `lowest_offer_listings_*_new`
freshness by `time`), see [`LOWEST_OFFER_COVERAGE.md`](LOWEST_OFFER_COVERAGE.md).

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

**Prepare upload:** marketplace commands that merge translations and write
upload NDJSON are documented in [`PREPARE_UPLOAD.md`](PREPARE_UPLOAD.md).

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

GCS CSV → **`em_inventory`**: full guide in [`INVENTORY_SYNC.md`](INVENTORY_SYNC.md)
(commands, YAML `sources`, CSV shape, cluster routing, prune, recipes).

| Command | Summary |
|---|---|
| `inventory sync [CONFIG_PATH]` | All `inventory_sync.sources` for current `APP_ENV` |
| `inventory sync-from-gcs [GS_URI]` | Single GCS CSV (env or CLI URI) |

```bash
APP_ENV=development ELASTICSEARCH_URL='http://…' bundle exec bin/em-tools inventory sync
bundle exec bin/em-tools inventory sync-from-gcs gs://em-bucket/Lazada_th-Inv.csv
```

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

**Prepare upload** (ES → upload NDJSON / ASIN lists for Lotteon, Oliveyoung,
Lazada, Amazon uploadable, shared keyword + translation options):
[`PREPARE_UPLOAD.md`](PREPARE_UPLOAD.md).

### Amazon uploadable (`plugins/amazon/uploadable/`)

Upload pipeline commands (`filter`, `upload-from-es`, `format-file`,
`build-feed`): see [`PREPARE_UPLOAD.md` — Amazon](PREPARE_UPLOAD.md#amazon-amazon-products-).

| Command | What it does |
|---|---|
| `amazon products export-by-top-category` | Export ASINs from `amz_products_api_<mp>_v2` into one file per `top_category`. |
| `amazon products top-category-stats` | Export all `top_category` values and document counts (TSV + JSON). |

```bash
ELASTICSEARCH_URL='http://34.44.148.50' \
bundle exec bin/em-tools amazon products top-category-stats \
  -m de -o tmp/amz_de_top_category_counts.tsv

bundle exec bin/em-tools amazon products export-by-top-category \
  -m de -o tmp/amz_de_by_top_category

bundle exec bin/em-tools amazon products export-by-top-category \
  -o tmp/amz_beauty_health \
  --marketplaces uk,ca,jp,mx,ae,in,it,fr \
  --beauty-health
```

`top-category-stats` writes `top_category` + `doc_count` (fast aggregation). Optional `counts.json` summary.

`export-by-top-category` writes `tmp/amz_de_by_top_category/<top_category>.txt` (one ASIN per line) and `manifest.json`.
With `--marketplaces`, each marketplace is written under `<output>/<mp>/`. Use `-c` to limit categories, or `--beauty-health` for localized Beauty + Health category names per marketplace (CA/MX/FR/IT/AE differ from DE).
Use `--category-from categories_first` to group by `categories[0].cat_name` instead of `top_category`.

### Amazon lowest-offer (`plugins/amazon/lowest_offer/`)

Ad-report / seed ASINs → query `lowest_offer_listings_<mp>_new` by `time` field:
[`LOWEST_OFFER_COVERAGE.md`](LOWEST_OFFER_COVERAGE.md).

| Command | What it does |
|---|---|
| `amazon coverage publish-snapshot [MARKETPLACES...]` | Publish lowest-offer coverage snapshots (one row per marketplace). |
| `amazon coverage download-and-publish` | Composite: `gcs download-seeds` then `coverage publish-snapshot`. |

### eBay (`plugins/ebay/`)

| Command | What it does |
|---|---|
| `ebay listings publish-snapshot [MARKETPLACE]` | eBay listings coverage snapshot (one row per marketplace). |
| `ebay products export-redirect-product-ids` | Export `product_id` where `redirect=true` and `redirect_url` contains `/p/`. |
| `ebay products export-nonexistent-product-ids` | Export `product_id` where `existence=false`. |
| `ebay inventory lookup-product-ids` | Map local eBay item ids → `product_id` (`user1_ebay_us_products`, `source` + `source_product_id`). |

### Storefront (`plugins/storefront/`)

| Command | What it does |
|---|---|
| `storefront import-products INPUT_PATH` | Filter local NDJSON product feeds against the rule engine. |
| `storefront inventory sync` | Spree CSV → `em_inventory` — see [`INVENTORY_SYNC.md`](INVENTORY_SYNC.md#storefront-inventory-sync--spree-csv-api). |
| `storefront unpublish-candidates` | Iterate ES inventory, run rules, write delisting candidates to `em_products_to_unpublish`. |

### SSG / Lotteon (`plugins/ssg/`, `plugins/lotteon/`)

| Command | What it does |
|---|---|
| `ssg products export` | Stream SSG products from Elasticsearch as NDJSON (raw shape). |
| `lotteon products export` | Stream Lotteon products as NDJSON (no upload pipeline). |
| `lotteon products build-upload-payload` | Upload NDJSON — see [`PREPARE_UPLOAD.md` — Lotteon](PREPARE_UPLOAD.md#lotteon). |

### Lazada (`plugins/lazada/` — Thailand / Malaysia)

| Command | What it does |
|---|---|
| `lazada products export` | NDJSON stream; `-m`; `--for-upload` applies formatter + filters. |
| `lazada products build-upload` | Upload NDJSON — see [`PREPARE_UPLOAD.md` — Lazada](PREPARE_UPLOAD.md#lazada-thailand--malaysia). |

### Oliveyoung (`plugins/oliveyoung/`)

| Command | What it does |
|---|---|
| `oliveyoung products export` | Stream Oliveyoung products as NDJSON (raw shape). |
| `oliveyoung products build-upload` | Upload NDJSON — see [`PREPARE_UPLOAD.md` — Oliveyoung](PREPARE_UPLOAD.md#oliveyoung). |

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
