# em-tools

**em-tools** is the [Everymarket](https://github.com/AriseshineSky)
**data-management platform** — a personal Ruby application that drives
Elasticsearch dumps, GCS-backed inventory sync, and per-marketplace coverage
snapshots (Amazon lowest-offer, Amazon uploadable, eBay listings, Korean
storefronts) through:

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
bundle exec bin/em-tools amazon-lowest-offer coverage publish-snapshot us ca jp   # Amazon snapshot
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

| Capability | Plugin / module | CLI command |
|---|---|---|
| Stream an ES index to NDJSON (any cluster) | `EmTools::Core::Sinks::IndexDumper` / `Config.elasticsearch_client` | `em-tools dump INDEX` |
| Env-driven ES dump (primary cluster) | `EmTools::Core::Sinks::IndexDumper.from_env` | `em-tools es dump-index` |
| Env-driven ES dump (data cluster) + blacklist policy | `EmTools::Core::Pipelines::ProductDownload` | `em-tools es download-product` |
| Sync GCS inventory CSVs into ES (multi-source) | `EmTools::Core::Inventory::*` | `em-tools inventory sync [path]` |
| Sync a single GCS CSV into ES | `EmTools::Core::Inventory::SyncRunner` | `em-tools inventory sync-from-gcs [gs://...]` |
| Download lowest-offer AMZ seed files from GCS | `Plugins::AmazonLowestOffer::Sources::SeedFiles` | `em-tools gcs download-seeds` |
| Amazon lowest-offer coverage snapshot | `Plugins::AmazonLowestOffer::Pipelines::PublishSnapshot` | `em-tools amazon-lowest-offer coverage publish-snapshot [mp ...]` |
| Seeds + Amazon snapshot in one go | composite of the two above | `em-tools amazon-lowest-offer coverage download-and-publish` |
| eBay listings coverage snapshot | `Plugins::Ebay::Pipelines::PublishSnapshot` | `em-tools ebay listings publish-snapshot [mp]` |
| Format Amazon uploadable products from a file | `Plugins::AmazonUploadable::Cli::*` | `em-tools amz-uploadable format-from-file` |
| Upload Amazon products from ES | `Plugins::AmazonUploadable::Cli::*` | `em-tools amz-uploadable upload-from-es` |
| Storefront → ES inventory + delisting candidates | `Plugins::Storefront::Runners::*` | `em-tools storefront sync-inventory` / `storefront unpublish-candidates` |
| Refresh keyword blacklist | `EmTools::Core::Blacklist::Loader` | `em-tools blacklist download` |

A full per-command reference lives in [`docs/CLI.md`](docs/CLI.md).

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
    amazon_uploadable/  amazon_lowest_offer/
    ebay/  storefront/  lotteon/  ssg/

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
| [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) | Know what to put in `.env` vs `config/settings.yml`. |
| [`docs/PLUGINS.md`](docs/PLUGINS.md) | Add a new plugin (or new CLI command to an existing one). |
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
| 04:00 | `em-tools amazon-lowest-offer coverage download-and-publish` (Amazon snapshot) |
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
