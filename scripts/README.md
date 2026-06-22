# scripts/

Shell wrappers for cron / manual runs. Business logic stays in `bin/em-tools`.

| Script | Command |
|--------|---------|
| `inventory-sync.sh` | Full sync — all `inventory_sync.sources` from `settings.yml` |
| `inventory-sync-from-gcs.sh` | Single GCS CSV → `em_inventory` |
| `uk-inventory-sync.sh` | UK site: `gs://em-uk/AMZ_US-Inv.csv` → `uk_inventory` (`APP_ENV=uk`) |
| `amazon-lowest-offer-snapshot.sh` | `em-tools amazon coverage download-and-publish` |
| `amazon-sync-user1-amz-asins.sh` | `em-tools amazon asins sync-user1` |
| `ebay-sync-user1-products.sh` | `em-tools ebay products sync-user1` |
| `elevenst-price-freshness-snapshot.sh` | `em-tools kr elevenst publish-price-freshness-snapshot` |

Use `EM_TOOLS_BUNDLE=/path/to/bundle` when cron cannot find `bundle` (rbenv/asdf).

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

See `docs/LOWEST_OFFER_COVERAGE.md`.

## Amazon user1 ASIN sync (hourly cron)

```bash
chmod +x scripts/amazon-sync-user1-amz-asins.sh
./scripts/amazon-sync-user1-amz-asins.sh --since-hours 3

# crontab -e
15 * * * * EM_TOOLS_BUNDLE=/home/sky/.rbenv/shims/bundle /home/sky/src/em-tools/scripts/amazon-sync-user1-amz-asins.sh --since-hours 3 >> /home/sky/src/em-tools/log/amazon-sync-user1-amz-asins.log 2>&1
```

## eBay user1 product sync (hourly cron)

```bash
chmod +x scripts/ebay-sync-user1-products.sh
./scripts/ebay-sync-user1-products.sh --since-hours 3

# crontab -e
25 * * * * EM_TOOLS_BUNDLE=/home/sky/.rbenv/shims/bundle /home/sky/src/em-tools/scripts/ebay-sync-user1-products.sh --since-hours 3 >> /home/sky/src/em-tools/log/ebay-sync-user1-products.log 2>&1
```

## 11ST price freshness snapshot (daily cron)

```bash
chmod +x scripts/elevenst-price-freshness-snapshot.sh
./scripts/elevenst-price-freshness-snapshot.sh

# crontab -e
30 5 * * * EM_TOOLS_BUNDLE=/home/sky/.rbenv/shims/bundle /home/sky/src/em-tools/scripts/elevenst-price-freshness-snapshot.sh >> /home/sky/src/em-tools/log/elevenst-price-freshness.log 2>&1
```

## UK inventory sync (daily cron)

```bash
chmod +x scripts/uk-inventory-sync.sh
./scripts/uk-inventory-sync.sh

# crontab -e
0 4 * * * /home/sky/src/em-tools/scripts/uk-inventory-sync.sh >> /home/sky/src/em-tools/log/uk-inventory-sync.log 2>&1
```

See `docs/INVENTORY_SYNC.md` (UK storefront section).
