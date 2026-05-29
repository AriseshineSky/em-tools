# scripts/

Shell wrappers for cron / manual runs. Business logic stays in `bin/em-tools`.

| Script | Command |
|--------|---------|
| `inventory-sync.sh` | Full sync — all `inventory_sync.sources` from `settings.yml` |
| `inventory-sync-from-gcs.sh` | Single GCS CSV → `em_inventory` |
| `amazon-lowest-offer-snapshot.sh` | `bin/amazon-lowest-offer-snapshot` (GCS seeds + coverage publish) |

## Full sync (daily cron)

```bash
chmod +x scripts/inventory-sync.sh
./scripts/inventory-sync.sh

# crontab -e
30 3 * * * /home/sky/src/em-tools/scripts/inventory-sync.sh >> /home/sky/src/em-tools/log/inventory-sync.log 2>&1
```

## Amazon lowest-offer snapshot (daily cron)

```bash
chmod +x scripts/amazon-lowest-offer-snapshot.sh
./scripts/amazon-lowest-offer-snapshot.sh

# crontab -e
0 4 * * * /home/sky/src/em-tools/scripts/amazon-lowest-offer-snapshot.sh >> /home/sky/src/em-tools/log/em-tools.lowest-offer.log 2>&1
```

Use `EM_TOOLS_BUNDLE=/path/to/bundle` when cron cannot find `bundle` (rbenv/asdf). See `docs/LOWEST_OFFER_COVERAGE.md`.
