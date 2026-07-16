# Scheduled jobs

em-tools is driven by two surfaces:

1. **Interactive / ad-hoc** — `bundle exec bin/em-tools <command>` from the
   repo. See [`docs/CLI.md`](../docs/CLI.md).
2. **Recurring / unattended** — cron or systemd timers running
   [`scripts/`](../scripts/) wrappers on a fixed schedule. Templates live in
   this directory.

This directory is **the source of truth** for scheduled jobs: every recurring
em-tools workflow gets a template here. Production deployments install (or
symlink) the rendered version into `/etc/cron.d/` or
`/etc/systemd/system/`.

```
schedule/
├── README.md                                 (this file)
├── cron.example                              all jobs in one cron file
├── cron.inventory-sync.example                 single-job: daily full inventory sync
├── cron.amazon-lowest-offer.example            single-job: daily lowest-offer snapshot
├── cron.amazon-sync-user1-amz-asins.example      hourly user1_amz_asins -> amz_asins_<mp> sync
├── cron.ebay-sync-user1-products.example         twice-daily user1_ebay_products sync (24h)
├── cron.elevenst-price-freshness.example         daily 11ST price freshness snapshot
└── systemd/
    ├── em-tools-inventory-sync.service.example
    ├── em-tools-inventory-sync.timer.example
    ├── em-tools-lowest-offer-snapshot.service.example
    ├── em-tools-lowest-offer-snapshot.timer.example
    ├── em-tools-ebay-listings-snapshot.service.example
    └── em-tools-ebay-listings-snapshot.timer.example
```

## Picking cron vs systemd

| If you want | Use |
|---|---|
| Cron + shell script (recommended if you skip systemd) | [`../scripts/`](../scripts/) + matching `cron.*.example` |
| One file, all jobs | [`cron.example`](cron.example) |
| Per-job journalctl, timeout, run-on-boot | [`systemd/`](systemd/) (optional) |

Cron jobs call the same logic as `bundle exec bin/em-tools …`; the shell
scripts add `flock`, logging hooks, and `APP_ENV` where needed.

## Cron quickstart

```bash
sudo cp schedule/cron.example /etc/cron.d/em-tools
sudoedit /etc/cron.d/em-tools          # edit User= and absolute paths
sudo systemctl reload cron             # cronie / cronie-anacron on Manjaro
```

`cron.example` runs jobs as a non-root user and emits stdout/stderr to
`log/em-tools.<job>.log`. Each `scripts/*.sh` wrapper `cd`s into the repo so
`bin/em-tools` loads `.env` via dotenv.

| Job | Script | Example cron |
|-----|--------|--------------|
| Full inventory sync | [`inventory-sync.sh`](../scripts/inventory-sync.sh) | [`cron.inventory-sync.example`](cron.inventory-sync.example) |
| Amazon lowest-offer | [`amazon-lowest-offer-snapshot.sh`](../scripts/amazon-lowest-offer-snapshot.sh) | [`cron.amazon-lowest-offer.example`](cron.amazon-lowest-offer.example) |
| user1_amz_asins sync | [`amazon-sync-user1-amz-asins.sh`](../scripts/amazon-sync-user1-amz-asins.sh) | [`cron.amazon-sync-user1-amz-asins.example`](cron.amazon-sync-user1-amz-asins.example) |
| user1_ebay_products sync | [`ebay-sync-user1-products.sh`](../scripts/ebay-sync-user1-products.sh) | [`cron.ebay-sync-user1-products.example`](cron.ebay-sync-user1-products.example) |
| 11ST price freshness | [`elevenst-price-freshness-snapshot.sh`](../scripts/elevenst-price-freshness-snapshot.sh) | [`cron.elevenst-price-freshness.example`](cron.elevenst-price-freshness.example) |
| 11ST recrawl queue keeper | [`elevenst-recrawl-queue-keeper.sh`](../scripts/elevenst-recrawl-queue-keeper.sh) | [`systemd/em-tools-elevenst-recrawl-keeper.service.example`](systemd/em-tools-elevenst-recrawl-keeper.service.example) |

Per-marketplace Amazon ASIN jobs use `-m <code>` (e.g. `-m br` for Brazil).

### rbenv / explicit `bundle` path

cron does not load your login shell PATH, so `bundle` may not resolve. Set
`EM_TOOLS_BUNDLE` to the absolute shim path (e.g.
`/home/Admin/.rbenv/shims/bundle`) on the cron line:

```bash
EM_TOOLS_BUNDLE=/home/Admin/.rbenv/shims/bundle /home/Admin/src/em-tools/scripts/amazon-lowest-offer-snapshot.sh
```

## systemd quickstart

```bash
sudo cp schedule/systemd/em-tools-inventory-sync.service.example \
        /etc/systemd/system/em-tools-inventory-sync.service
sudo cp schedule/systemd/em-tools-inventory-sync.timer.example \
        /etc/systemd/system/em-tools-inventory-sync.timer
sudoedit /etc/systemd/system/em-tools-inventory-sync.service
sudoedit /etc/systemd/system/em-tools-inventory-sync.timer

sudo systemctl daemon-reload
sudo systemctl enable --now em-tools-inventory-sync.timer
systemctl list-timers em-tools-inventory-sync.timer
journalctl -u em-tools-inventory-sync.service -e
```

Repeat for each job you want. The unit names are deliberately
`em-tools-<job>.{service,timer}` so they sort together in
`systemctl list-timers`.

## Shared environment

Every scheduled job needs at least:

- `ELASTICSEARCH_URL` (and credentials).
- `GCS_SERVICE_ACCOUNT_PATH` (or `GCS_CREDENTIALS`).

These come from `.env` in the repo. The systemd templates source `.env` via
`EnvironmentFile=`; cron jobs rely on `bin/em-tools` loading dotenv when the
script `cd`s into the repo. **Do not** copy secrets into unit files.

## Adding a new scheduled job

1. Pick an `em-tools` subcommand (`bundle exec bin/em-tools <cmd> --help`).
2. Decide cadence (cron crontab spec or `OnCalendar=` for systemd).
3. Add a `scripts/<job>.sh` wrapper (see existing scripts for `flock` / logging).
4. Either:
   - Add a line to `cron.example`, or
   - Add `cron.<job>.example`, or
   - Copy `em-tools-inventory-sync.service.example` /
     `.timer.example` to `em-tools-<job>.service.example` /
     `.timer.example` and adjust the `ExecStart=` and schedule.
5. Mention the job in this README's table above.
