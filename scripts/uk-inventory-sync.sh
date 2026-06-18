#!/usr/bin/env bash
# UK site inventory sync: gs://em-uk/AMZ_US-Inv.csv -> uk_inventory (ELASTICSEARCH_URL).
#
# Usage:
#   ./scripts/uk-inventory-sync.sh
#
# Cron example (daily 04:00 UTC):
#   0 4 * * * /home/sky/src/em-tools/scripts/uk-inventory-sync.sh >> /home/sky/src/em-tools/log/uk-inventory-sync.log 2>&1
#
# Requires in .env:
#   ELASTICSEARCH_URL=http://user:pass@34.44.148.50:80
#   GCS_SERVICE_ACCOUNT_PATH=/path/to/gcs-sa.json

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_ENV=uk
export APP_ENV
BUNDLE="${EM_TOOLS_BUNDLE:-bundle}"
LOG_DIR="${LOG_DIR:-$ROOT/log}"

mkdir -p "$LOG_DIR"

echo "[uk-inventory-sync] start=$(date -u +"%Y-%m-%dT%H:%M:%SZ") app_env=${APP_ENV}"
# Per-source index in settings.yml wins over INVENTORY_INDEX in .env (em_inventory).
"$BUNDLE" exec bin/em-tools inventory sync
echo "[uk-inventory-sync] done=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
