# Inventory sync — GCS CSV → `em_inventory`

How to load **operating inventory** from Google Cloud Storage (or Spree) into
the shared Elasticsearch index **`em_inventory`**. Every marketplace plugin
(Amazon lowest-offer, Lazada prepare-upload skip lists, storefront unpublish, etc.)
reads this index.

For **upload NDJSON** generation (downstream of inventory), see
[`PREPARE_UPLOAD.md`](PREPARE_UPLOAD.md). For the full CLI index, see
[`CLI.md`](CLI.md).

**Not this doc:** `google-ads catalog sync` writes to **`google_ads_products`**
(ads SKU catalog), not `em_inventory`. See [`CLI.md`](CLI.md#google-ads-catalog-sync-config_path).

---

## What gets synced

| Item | Value |
|---|---|
| ES index | `em_inventory` (override: `INVENTORY_INDEX` or YAML `inventory_sync.index`) |
| Source files | GCS `gs://…/*.csv` (default format) |
| CLI (batch) | `em-tools inventory sync` |
| CLI (single file) | `em-tools inventory sync-from-gcs [GS_URI]` |
| Config | `config/settings.yml` → `inventory_sync.sources` (per `APP_ENV`) |
| Code | `lib/em_tools/core/inventory/` |

---

## End-to-end flow

```mermaid
sequenceDiagram
    participant Op as Operator / cron
    participant CLI as inventory sync
    participant SS as SyncSources
    participant GCS as GcsBlobFetcher
    participant Sync as Inventory::Sync
    participant ES as em_inventory

    Op->>CLI: bundle exec bin/em-tools inventory sync
    CLI->>SS: load settings (APP_ENV)
    SS-->>CLI: expanded gs:// URIs
    loop each source
        CLI->>GCS: download CSV
        GCS->>Sync: sync_from_path
        Sync->>ES: bulk upsert (doc_as_upsert)
        opt prune_obsolete
            Sync->>ES: delete_by_query stale batch
        end
    end
    CLI-->>Op: Inventory sync done (N source(s))
```

1. **SyncSources** reads `inventory_sync.sources` and expands templates (e.g.
   `AMZ_{marketplace}-Inv.csv` → ten URIs).
2. **GcsBlobFetcher** downloads each object to a temp file.
3. **Inventory::Sync** parses CSV rows, builds documents, bulk-indexes in
   batches of 2000.
4. Optionally **prune** removes rows from the same `inventory_feed` that were
   not seen in this run.

---

## Prerequisites

### Elasticsearch

```bash
ELASTICSEARCH_URL='http://user:pass@host:9200'
```

For sources routed to the **data** cluster, also set `DATA_ELASTICSEARCH_URL`
(or pass `--data` on the CLI for sources without an explicit `cluster:` in YAML).

### Google Cloud Storage

Application Default Credentials or a service account file:

```bash
GCS_SERVICE_ACCOUNT_PATH=/path/to/service-account.json
# or GCS_CREDENTIALS + GCS_PROJECT_ID (see .env.example)
```

GCS console URLs like
`https://storage.cloud.google.com/em-bucket/Lazada_th-Inv.csv` map to:

```text
gs://em-bucket/Lazada_th-Inv.csv
```

### Active settings section

```bash
APP_ENV=development   # default if unset; selects development: / production: in settings.yml
```

Optional: `EM_TOOLS_SETTINGS_PATH=/abs/path/to/settings.yml` for a non-default YAML file.

---

## Commands

### `inventory sync` — all configured sources

Runs **every** entry in `inventory_sync.sources` for the active `APP_ENV`.
There is **no CLI flag** to sync “AMZ only”; control the list in YAML.

```bash
APP_ENV=development \
ELASTICSEARCH_URL='http://user:pass@host:9200' \
bundle exec bin/em-tools inventory sync
```

Alternate settings file:

```bash
bundle exec bin/em-tools inventory sync /path/to/custom-settings.yml
```

Default unmarked sources to the data cluster:

```bash
bundle exec bin/em-tools inventory sync --data
```

### `inventory sync-from-gcs` — one GCS object

Debug / ad-hoc single-file sync. URI from CLI argument, env, or bucket+object:

```bash
ELASTICSEARCH_URL='http://…' \
INVENTORY_INDEX=em_inventory \
bundle exec bin/em-tools inventory sync-from-gcs gs://em-bucket/AMZ_DE-Inv.csv
```

```bash
INVENTORY_GS_URI=gs://em-bucket/Lazada_th-Inv.csv \
bundle exec bin/em-tools inventory sync-from-gcs
```

```bash
INVENTORY_GCS_BUCKET=em-bucket \
INVENTORY_GCS_OBJECT=Lazada_th-Inv.csv \
bundle exec bin/em-tools inventory sync-from-gcs
```

Add `--data` to target `DATA_ELASTICSEARCH_URL` (same semantics as batch sync).

---

## Configuration (`config/settings.yml`)

Inventory paths and defaults live under **`inventory_sync`** in the merged
settings YAML. Only the section for the current **`APP_ENV`** is used
(`development` by default).

### Section defaults

```yaml
inventory_sync:
  cluster: primary          # default ES cluster for sources without cluster:
  index: em_inventory       # target index
  refresh: false            # _refresh index after each source bulk
  prune_obsolete: false     # delete stale docs per feed after sync
  sources: []               # list of gs:// URIs or hashes
```

| Key | Meaning |
|---|---|
| `cluster` | Section-wide ES cluster name: `primary`, `data`, or a custom `elasticsearch_clusters` key |
| `index` | Default ES index (overridden by `INVENTORY_INDEX` env if set) |
| `refresh` | When `true`, refresh index after bulk (slower; visible immediately) |
| `prune_obsolete` | When `true`, delete docs in the same feed not seen in this batch |
| `sources` | Non-empty list of GCS locations to sync |

### Per-source entries

**Bare URI** — one CSV file:

```yaml
sources:
  - gs://em-bucket/Lazada_th-Inv.csv
  - uri: gs://em-bucket/boyner-Inv.csv
```

**Hash** — overrides for one file:

```yaml
sources:
  - uri: gs://em-bucket/Ebay_US-Inv.csv
    cluster: data              # DATA_ELASTICSEARCH_URL
    index: em_inventory        # optional per-source index override
    refresh: true
    prune_obsolete: true
    feed_id: EBAY_US           # pin inventory_feed when CSV Source col is empty/wrong
    drop_fields: handle,variants
```

**Template** — one YAML row → many Amazon files:

```yaml
sources:
  - gs_uri_template: gs://em-bucket/AMZ_{marketplace}-Inv.csv
    marketplaces: all
```

Aliases for the template key: `gs_uri_template`, `template`, `uri_template`.

#### `{marketplace}` expansion

The placeholder `{marketplace}` is replaced with each marketplace **code**
(string substitution), producing URIs like `gs://em-bucket/AMZ_DE-Inv.csv`.

| `marketplaces` | Expanded codes |
|---|---|
| `all` | `AE`, `CA`, `US`, `DE`, `UK`, `IN`, `IT`, `MX`, `JP`, `TR` |
| `[DE, UK]` | `DE`, `UK` (uppercased) |
| `"TR,DE"` | `TR`, `DE` |

The code is the **filename token** (`AMZ_DE`), not an AWS marketplace API id.

### Example: AMZ + eBay + Lazada + 11ST

From `config/settings.yml` (`development`):

```yaml
development:
  inventory_sync:
    cluster: primary
    index: em_inventory
    refresh: false
    prune_obsolete: false
    sources:
      - gs_uri_template: gs://em-bucket/AMZ_{marketplace}-Inv.csv
        marketplaces: all
      - uri: gs://em-bucket/Ebay_US-Inv.csv
        cluster: data
      - uri: gs://em-bucket/Lazada_th-Inv.csv
      - uri: gs://em-bucket/11ST-Inv.csv
        cluster: data
```

`inventory sync` runs **all** of the above in one invocation (11 AMZ files +
eBay + Lazada + 11ST). Comment out entries you do not want.

---

## Elasticsearch cluster routing

Precedence **per source** (highest wins):

1. Source `cluster:` in YAML
2. Section `inventory_sync.cluster:`
3. CLI `--data` (treats unmarked sources as `data`)
4. `ELASTICSEARCH_URL` (`primary`)

| Cluster name | Env / config |
|---|---|
| `primary` | `ELASTICSEARCH_URL` |
| `data` / `analytics` | `DATA_ELASTICSEARCH_URL` (falls back to primary) |
| custom | `ELASTICSEARCH_CLUSTER_<NAME>_URL` or `elasticsearch_clusters.<name>.url` in YAML |

---

## Environment variables

| Variable | Used by | Purpose |
|---|---|---|
| `ELASTICSEARCH_URL` | both commands | Primary cluster (required) |
| `DATA_ELASTICSEARCH_URL` | `--data` / `cluster: data` | Data cluster |
| `INVENTORY_INDEX` | both | Target index (default `em_inventory`) |
| `INVENTORY_GS_URI` | `sync-from-gcs` | Single `gs://` URI |
| `INVENTORY_GCS_BUCKET` | `sync-from-gcs` | With `INVENTORY_GCS_OBJECT` |
| `INVENTORY_GCS_OBJECT` | `sync-from-gcs` | Object path in bucket |
| `INVENTORY_REFRESH` | `sync-from-gcs` | Set `1` to refresh after bulk |
| `INVENTORY_PRUNE_OBSOLETE` | `sync-from-gcs` | Set `1` to prune after sync |
| `INVENTORY_FEED_ID` | `sync-from-gcs` | Fallback feed when CSV has no `Source` |
| `INVENTORY_DROP_FIELDS` | `sync-from-gcs` | Comma-separated fields to strip before bulk |
| `GCS_SERVICE_ACCOUNT_PATH` | both | GCS credentials file |
| `APP_ENV` | `inventory sync` | Which YAML section to load |

YAML `refresh` / `prune_obsolete` / `feed_id` on each source override section
defaults for batch sync. Per-source `drop_fields` is supported in YAML only.

---

## CSV file format (default)

Inventory sync expects a **header row** and one product per line (standard CSV).

### Document `_id`

First non-empty value among (snake_case field names on the document):

`product_id` → `sku` → `asin` → `id`

Typical header: **`ProductID`** → stored as `product_id` and used as ES `_id`.

### Column names → ES fields

Headers are normalized to **snake_case** (`SourceProductID` →
`source_product_id`, `Product ID` → `product_id`). Empty cells are omitted.

### Fields added by sync

| Field | Meaning |
|---|---|
| `sync_batch_id` | UUID for this sync run (used by prune) |
| `synced_at` | ISO8601 UTC timestamp |
| `inventory_feed` | Feed key for prune + filtering (see below) |
| `source` | From CSV `Source` column when present |

### `Source` column and `inventory_feed`

- CSV column **`Source`** becomes field **`source`** and drives **`inventory_feed`**.
- **One CSV file must not mix multiple `Source` values.** Case-only differences
  (`Ebay_US` vs `EBAY_US`) are normalized; truly different values raise an error.
- Set YAML **`feed_id:`** (or `INVENTORY_FEED_ID` on single-file sync) to pin
  `inventory_feed` for every row when the CSV has no `Source` column or you need
  a canonical name (e.g. `lazadacoth` for Lazada TH prepare-upload).

### Align `source` with downstream tools

| Channel | Typical `source` / `inventory_feed` in `em_inventory` |
|---|---|
| Amazon DE | `AMZ_DE` |
| eBay US | `Ebay_US` / `EBAY_US` (keep consistent within a feed) |
| Lazada TH | `lazadacoth` (matches `lazada_marketplaces.th.inventory_source`) |
| Lotteon | `lotteon` |
| Oliveyoung | `oliveyoung` |
| Boyner | `Boyner` |

Prepare-upload commands use `--inventory-source` to skip SKUs already present
in `em_inventory` for that feed. See [`PREPARE_UPLOAD.md`](PREPARE_UPLOAD.md).

---

## Upsert vs delete (prune)

### Default: upsert only

Without prune, sync **updates or inserts** rows from the CSV. Documents that
exist in ES but are **absent from the CSV are left unchanged**.

### `prune_obsolete: true` — remove stale rows per feed

When enabled (YAML per source/section, or `INVENTORY_PRUNE_OBSOLETE=1` on
`sync-from-gcs`):

1. Each indexed row gets the run’s `sync_batch_id`.
2. After bulk (+ optional refresh), a **`delete_by_query`** removes documents where:
   - `inventory_feed.keyword` = this feed’s id, **and**
   - `sync_batch_id` ≠ current batch id.

**Scope:** only the **same `inventory_feed`** — other feeds in `em_inventory`
are untouched. This is how a feed goes from “rows in CSV” to “what’s currently
live” for that source.

**Requirements:**

- Non-empty `inventory_feed` (from CSV `Source` or `feed_id` / `INVENTORY_FEED_ID`).
- Sink must support `refresh` and `delete_by_query`.

**Caution:** on large indexes, prune can time out (504). Default in
`config/settings.yml` is `prune_obsolete: false`.

---

## Common recipes

### Sync all Amazon marketplaces (from template)

Ensure `development.inventory_sync.sources` includes the AMZ template, then:

```bash
APP_ENV=development ELASTICSEARCH_URL='http://…' \
bundle exec bin/em-tools inventory sync
```

### Sync one Amazon marketplace only

```bash
bundle exec bin/em-tools inventory sync-from-gcs gs://em-bucket/AMZ_US-Inv.csv
```

Or temporarily set `marketplaces: [US]` on the template entry.

### Add a new non-AMZ source (e.g. Lazada TH)

1. Upload CSV to GCS: `gs://em-bucket/Lazada_th-Inv.csv`.
2. Add to `inventory_sync.sources`:

   ```yaml
   - uri: gs://em-bucket/Lazada_th-Inv.csv
     feed_id: lazadacoth    # optional; use if CSV Source col differs
   ```

3. Run `inventory sync` or single-file `sync-from-gcs`.
4. Verify in ES: documents with matching `source` / `inventory_feed`.

### Sync with prune for one feed

```bash
INVENTORY_PRUNE_OBSOLETE=1 \
INVENTORY_REFRESH=1 \
INVENTORY_FEED_ID=lazadacoth \
bundle exec bin/em-tools inventory sync-from-gcs gs://em-bucket/Lazada_th-Inv.csv
```

---

## Alternative source: Spree storefront

When inventory CSVs are served by your **Spree** storefront API instead of GCS:

```bash
EM_TOOLS_SITE_STOREFRONT_ENDPOINT='https://…' \
EM_TOOLS_SITE_STOREFRONT_TOKEN='…' \
bundle exec bin/em-tools storefront inventory sync --source AMZ_AE,AMZ_CA
```

| Flag | Default | Notes |
|---|---|---|
| `--source` | (required) | Repeatable; comma-separated OK |
| `--index` | `em_inventory` | Override index |
| `--refresh` | `true` | Refresh after sync |
| `--prune` | `true` | Prune stale docs per source (opposite default from GCS sync) |

Configure `sites.storefront` in `config/settings.yml` for non-secret defaults;
see [`CONFIGURATION.md`](CONFIGURATION.md).

---

## Scheduled runs

Examples in the repo:

| Mechanism | File |
|---|---|
| cron | `schedule/cron.example` — daily `03:30` `inventory sync` |
| systemd | `schedule/systemd/em-tools-inventory-sync.{service,timer}.example` |

Both invoke:

```bash
cd /path/to/em-tools && bundle exec bin/em-tools inventory sync
```

Ensure `.env`, GCS credentials, and `APP_ENV` are set for the service user.
See [`schedule/README.md`](../schedule/README.md).

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `No inventory sync sources` | Empty `inventory_sync.sources` for current `APP_ENV` |
| `expected gs://bucket/path` | URI missing bucket path or wrong scheme |
| `inventory CSV mixes Source values` | Multiple `Source` values in one file; set `feed_id` or split files |
| `prune_obsolete needs a non-empty inventory_feed` | Missing `Source` column and no `feed_id` |
| `set ELASTICSEARCH_URL` | Cluster URL not in environment |
| GCS 403 / auth errors | Check `GCS_SERVICE_ACCOUNT_PATH` and bucket IAM |
| Documents in wrong cluster | Check per-source `cluster:` and `--data` |

---

## Who reads `em_inventory`

| Consumer | Use |
|---|---|
| `lazada` / `lotteon` / `oliveyoung` build-upload | Skip already-uploaded SKUs (`--inventory-source`) |
| `amazon coverage publish-snapshot` | `LOWEST_OFFER_ID_SOURCE=inventory` ASIN set — see [`LOWEST_OFFER_COVERAGE.md`](LOWEST_OFFER_COVERAGE.md) |
| `storefront unpublish-candidates` | Delisting rule input |
| `google-ads catalog missing-product-ids` | Set diff vs ads catalog |

---

## Related docs

| Doc | Topic |
|---|---|
| [`CLI.md`](CLI.md) | Command index, exit codes, Google Ads catalog |
| [`CONFIGURATION.md`](CONFIGURATION.md) | `.env` vs YAML split, exporters, sites |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Code layout under `core/inventory/` |
| [`PREPARE_UPLOAD.md`](PREPARE_UPLOAD.md) | ES → upload NDJSON after inventory is loaded |
