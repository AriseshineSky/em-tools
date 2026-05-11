# Scheduled jobs

em-tools is driven by two surfaces:

1. **Interactive / ad-hoc** — `bundle exec bin/em-tools <command>` from the
   repo. See [`docs/CLI.md`](../docs/CLI.md).
2. **Recurring / unattended** — cron or systemd timers running the same
   commands on a fixed schedule. Templates live in this directory.

This directory is **the source of truth** for scheduled jobs: every recurring
em-tools workflow gets a template here. Production deployments install (or
symlink) the rendered version into `/etc/cron.d/` or
`/etc/systemd/system/`.

```
schedule/
├── README.md                                 (this file)
├── cron.example                              all jobs in one cron file
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
| One file, one operator, simple shell semantics | [`cron.example`](cron.example) |
| Per-job logs (journalctl), retry/timeout/state machine, run-on-boot catch-up | [`systemd/`](systemd/) |

Both surfaces invoke **exactly the same CLI binary** (`bin/em-tools`); pick
whichever fits your host. Manjaro / Arch hosts default to systemd, so the
systemd templates are the most exercised path.

## Cron quickstart

```bash
sudo cp schedule/cron.example /etc/cron.d/em-tools
sudoedit /etc/cron.d/em-tools          # edit User= and absolute paths
sudo systemctl reload cron             # cronie / cronie-anacron on Manjaro
```

`cron.example` runs jobs as a non-root user, sources `.env` from the repo,
and emits stdout/stderr to `log/em-tools.<job>.log`.

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
`EnvironmentFile=`; the cron template sources it via a small `bash -lc`
wrapper. **Do not** copy secrets into unit files.

## Adding a new scheduled job

1. Pick an `em-tools` subcommand (`bundle exec bin/em-tools <cmd> --help`).
2. Decide cadence (cron crontab spec or `OnCalendar=` for systemd).
3. Either:
   - Add a line to `cron.example`, or
   - Copy `em-tools-inventory-sync.service.example` /
     `.timer.example` to `em-tools-<job>.service.example` /
     `.timer.example` and adjust the `ExecStart=` and schedule.
4. Mention the job in this README's table above.
