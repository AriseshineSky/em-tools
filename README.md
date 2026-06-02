# em-tools

**em-tools** is the [Everymarket](https://github.com/AriseshineSky)
**data-management platform** — a personal Ruby application that drives
Elasticsearch dumps, GCS-backed inventory sync, and per-marketplace coverage
snapshots. The **Amazon** workstreams share one `:amazon` plugin (uploadable
products + lowest-offer coverage); **eBay** listings, **storefront** (Spree),
and Korean marketplace exporters (**SSG**, **Lotteon**, **Oliveyoung**) each
have their own plugin scopes. Everything is exposed through:

1. **A single CLI** at [`bin/em-tools`](bin/em-tools) for ad-hoc /
   interactive use.
2. **A `schedule/` directory** of cron + systemd templates for unattended
   recurring jobs.

It is **not a gem**. There is no `.gemspec`, no `rake build/install/release`
flow, no rubygems publishing. Run it from a checkout, point cron / systemd
at `bin/em-tools`, done.

---

## Table of contents

- [Quickstart](#quickstart)
- [Running commands](#running-commands)
- [What is in the box](#what-is-in-the-box)
- [Project layout](#project-layout)
- [Documentation map](#documentation-map)
- [Development](#development)
- [Scheduled jobs](#scheduled-jobs)
- [License](#license)

---

## Quickstart

```bash
git clone git@github.com:AriseshineSky/em-tools.git
cd em-tools
bin/setup                          # bundle install + copy .env.example -> .env
$EDITOR .env                       # fill in cluster URLs / GCS keys

bundle exec bin/em-tools                                                    # top-level command tree
bundle exec bin/em-tools inventory sync                                     # all sources from settings YAML
bundle exec bin/em-tools amazon coverage publish-snapshot us ca jp   # Amazon snapshot
bundle exec bin/em-tools ebay listings publish-snapshot us                  # eBay snapshot
```

## Running commands

The CLI is a hierarchical subcommand tree (à la `kubectl` / `git`) built on
[dry-cli](https://dry-rb.org/gems/dry-cli/):

```
em-tools <area> <action> [options] [arguments]
```

Three equivalent invocation styles — pick whichever fits your shell habits:

```bash
# 1) bundle exec (works in any directory of the repo).
bundle exec bin/em-tools inventory sync

# 2) Run the script directly. `bin/em-tools` does its own `bundler/setup`
#    and `dotenv/load`, so a bare `./bin/em-tools` works from the repo root.
./bin/em-tools inventory sync

# 3) Add a shim once, then forget about paths.
ln -s "$(pwd)/bin/em-tools" ~/.local/bin/em-tools
em-tools inventory sync
```

### Help / discovery

```bash
bundle exec bin/em-tools                                  # top-level subtrees
bundle exec bin/em-tools <area>                           # subcommand listing
bundle exec bin/em-tools <area> <action> --help           # per-command help
```

For per-command reference and configuration, see
[`docs/CLI.md`](docs/CLI.md) and [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md).

---

## What is in the box

Below is a **command → purpose** map; flags, env vars, and exit codes are in
[`docs/CLI.md`](docs/CLI.md). Every command is invoked as
`bundle exec bin/em-tools …` (or `./bin/em-tools …` from the repo root).

### Core (no plugin namespace)

| Command | What it does |
|---|---|
| `dump INDEX` | Stream all documents from an Elasticsearch index as NDJSON (cluster selectable). |
| `es dump-index` | Env-driven dump from the **primary** cluster using `ES_DUMP_*` variables. |
| `es download-product` | Env-driven dump from the **data** cluster with blacklist keyword filtering. |
| `es translate-titles INDEX` | Scan an ES index; translate KO/JA-looking titles to English via a **translation sidecar index** (`--translation-index`, doc `_id` = hash of `source` + `source_product_id`) and/or product `title_en`; exporters can merge from that index (`--translation-index` on Oliveyoung / Lotteon). |
| `inventory sync [CONFIG_PATH]` | Sync one or more GCS inventory CSV feeds into ES per `config/settings.yml`. |
| `inventory sync-from-gcs [GS_URI]` | Sync a **single** GCS object into the inventory index. |
| `gcs download-seeds` | Download Amazon lowest-offer seed files (`amz_<mp>.txt`) from GCS into `./tmp`. |
| `blacklist download` | Fetch the keyword blacklist from the admin API (stdout or `--output`). |

### Amazon (`:amazon` plugin — `amazon` CLI namespace)

| Command | What it does |
|---|---|
| `amazon products filter` | Stream / filter uploadable ASINs from the Amazon ASIN index (rule engine slice). |
| `amazon products upload-from-es` | Read filtered products from ES and run the upload-side pipeline (Celery-compat config). |
| `amazon products format-file PATH` | Turn a local product file into the upload pipeline’s input shape. |
| `amazon products index-asins` | Stage ASIN-keyed product documents from the ASIN stream into ES (`mget` + bulk). |
| `amazon products build-feed` | Build uploadable feed rows from an ASIN source into JSONL / ES sinks. |
| `amazon coverage publish-snapshot [mp …]` | Publish lowest-offer **coverage** snapshots (one row per marketplace). See [`docs/LOWEST_OFFER_COVERAGE.md`](docs/LOWEST_OFFER_COVERAGE.md). |
| `amazon coverage download-and-publish` | Composite: `gcs download-seeds` then `amazon coverage publish-snapshot`. |

### eBay

| Command | What it does |
|---|---|
| `ebay listings publish-snapshot [mp]` | eBay listings coverage snapshot (one row per marketplace). |

### Storefront (Spree)

| Command | What it does |
|---|---|
| `storefront import-products INPUT_PATH` | Filter local product NDJSON through the rule engine. |
| `storefront inventory sync` | Download per-source inventory CSVs from Spree and bulk-index into ES. |
| `storefront unpublish-candidates` | Scan ES inventory, apply rules, write delisting candidates to `em_products_to_unpublish`. |

### Korean marketplace exporters

| Command | What it does |
|---|---|
| `ssg products export` | Stream SSG-tagged products from Elasticsearch as NDJSON. |
| `lotteon products export` | Stream Lotteon products from Elasticsearch as NDJSON. |
| `lotteon products build-upload-payload` | Read Lotteon products from ES, run **format then refine** transform stages (YAML / Ruby composable pipeline), optional keyword policy, write upload NDJSON. |
| `oliveyoung products export` | Stream Oliveyoung products from Elasticsearch as NDJSON. |
| `oliveyoung products build-upload` | Download Oliveyoung products from ES and write storefront-upload NDJSON (formatter + price rules). |
| `lazada products export` | Stream Lazada products; **`-m th`** / **`-m my`** picks marketplace (`exporters.lazada_th_products` / `lazada_my_products` + optional `lazada_marketplaces` YAML). |
| `lazada products build-upload` | Upload NDJSON (`tmp/lazada_<m>_upload.ndjson`); per-profile formatter, filters, and translation defaults. |

---

## Project layout

```
bin/                                  project executables
  em-tools                            the CLI (run as +bundle exec bin/em-tools+)
  console                             IRB with em-tools loaded
  setup                               bundle install + .env scaffold

lib/em_tools.rb                       Zeitwerk + plugin auto-load
lib/em_tools/
  error.rb                            EmTools::Error (gem-wide base class)
  version.rb                          EmTools::VERSION
  core/                               engine, errors, settings, CLI plumbing
    cli/{app,runner,commands/}
    inventory/                        multi-source GCS -> ES sync
    sinks/                            generic ES bulk + index dumper
    plugin/                           plugin base class
    plugin_registry.rb
    pipeline_engine.rb
    rules/                            rule strategies + registry
    blacklist/                        blacklist engine + Aho-Corasick store
    settings_loader.rb / settings_hydrator.rb
    config.rb / errors.rb / logger.rb
  clients/                            external service clients
    elasticsearch_client.rb spree_client.rb gcs_blob_fetcher.rb
    gcs_service_account_path.rb exchange_rate.rb
  plugins/                            one directory per plugin scope
    amazon/
      plugin.rb                         registers :amazon (uploadable + lowest-offer CLI)
      uploadable/  lowest_offer/       Amazon implementation trees
    ebay/  storefront/  lotteon/  oliveyoung/  ssg/  lazada/

config/settings.yml                   structural / routing config (no secrets)
.env.example                          secrets and cluster URLs
schedule/                             cron + systemd templates for recurring jobs
  cron.example
  systemd/em-tools-*.service.example
  systemd/em-tools-*.timer.example
docs/                                 OVERVIEW, CLI, CONFIGURATION, PLUGINS, ARCHITECTURE
log/                                  (gitignored) cron output
tmp/                                  (gitignored) seed downloads, NDJSON dumps
spec/                                 RSpec mirror of lib/
```

Secrets and cluster URLs live in `.env`; structural choices (cluster names,
GCS object lists, inventory feed names) live in `config/settings.yml`. See
[`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) for the full split.

---

## Documentation map

| File | Read this when you want to… |
|---|---|
| [`docs/OVERVIEW.md`](docs/OVERVIEW.md) | Understand the data platform end-to-end (mermaid diagrams). |
| [`docs/CLI.md`](docs/CLI.md) | See every CLI command, args, env vars, and exit codes. |
| [`docs/INVENTORY_SYNC.md`](docs/INVENTORY_SYNC.md) | Sync GCS / Spree inventory CSVs into `em_inventory` (YAML, prune, recipes). |
| [`docs/PREPARE_UPLOAD.md`](docs/PREPARE_UPLOAD.md) | Prepare upload NDJSON (Amazon, Lotteon, Oliveyoung, Lazada, shared translation/blacklist flow). |
| [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) | Know what to put in `.env` vs `config/settings.yml`. |
| [`docs/PLUGINS.md`](docs/PLUGINS.md) | Add a new plugin (or new CLI command to an existing one). |
| [`docs/PLUGIN_BOUNDARIES.md`](docs/PLUGIN_BOUNDARIES.md) | Plugin 按渠道划分的设计理由；新能力放 Core 还是 plugin（中文备忘）。 |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Map files / namespaces / Zeitwerk + plugin engine internals. |
| [`docs/DDD_AND_UBIQUITOUS_LANGUAGE.md`](docs/DDD_AND_UBIQUITOUS_LANGUAGE.md) | Domain language and bounded contexts. |
| [`schedule/README.md`](schedule/README.md) | Wire up cron / systemd jobs. |
| [`docs/notes/`](docs/notes/) | Historical migration notes (not source of truth). |

---

## Development

```bash
bin/setup                              # one-time
bundle exec rspec
bundle exec rubocop
bundle exec bin/em-tools help          # smoke
bundle exec bin/console                # IRB with em-tools loaded
```

The Rakefile only exposes `rake spec` (alias for `bundle exec rspec`). There
are no business rake tasks — every operational workflow is a CLI subcommand.

Linting follows [**rubocop-shopify**](https://github.com/Shopify/ruby-style-guide);
see [`.rubocop.yml`](.rubocop.yml) for the few project-specific overrides.

Ruby version: see [`.ruby-version`](.ruby-version).

---

## Scheduled jobs

Recurring jobs are first-class. Templates live in
[`schedule/`](schedule/README.md):

```bash
# systemd (recommended on Manjaro / Arch / any modern Linux).
sudo cp schedule/systemd/em-tools-inventory-sync.service.example \
        /etc/systemd/system/em-tools-inventory-sync.service
sudo cp schedule/systemd/em-tools-inventory-sync.timer.example \
        /etc/systemd/system/em-tools-inventory-sync.timer
sudoedit /etc/systemd/system/em-tools-inventory-sync.service
sudo systemctl daemon-reload
sudo systemctl enable --now em-tools-inventory-sync.timer

# Or cron, if you prefer.
sudo cp schedule/cron.example /etc/cron.d/em-tools
sudoedit /etc/cron.d/em-tools
```

The example schedule:

| Time (system TZ) | Job |
|---|---|
| 03:30 | `em-tools inventory sync` (full sync) |
| 04:00 | `em-tools amazon coverage download-and-publish` (Amazon snapshot) |
| 04:30 | `em-tools ebay listings publish-snapshot us` (eBay snapshot) |
| 05:00 | `em-tools storefront unpublish-candidates` (delisting candidates) |

See [`schedule/README.md`](schedule/README.md) for the full guide.

---

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md). PRs that change behaviour or
configuration should also update [`CHANGELOG.md`](CHANGELOG.md) under
`[Unreleased]`.

To add a plugin, follow [`docs/PLUGINS.md`](docs/PLUGINS.md).

---

## License

[MIT](LICENSE.txt). © Everymarket.
