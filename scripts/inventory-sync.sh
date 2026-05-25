#!/usr/bin/env bash
# Full inventory sync: all GCS sources from config/settings.yml -> em_inventory.
#
# Usage:
#   ./scripts/inventory-sync.sh
#   APP_ENV=production ./scripts/inventory-sync.sh
#   ./scripts/inventory-sync.sh --data
#
# Cron (daily 03:30, log to repo log/):
#   30 3 * * * /home/Admin/src/em-tools/scripts/inventory-sync.sh >> /home/Admin/src/em-tools/log/inventory-sync.log 2>&1
#
# Stale-doc cleanup: set prune_obsolete: true in settings.yml for your APP_ENV
# (INVENTORY_PRUNE_OBSOLETE in .env applies to sync-from-gcs only).
#
# See docs/INVENTORY_SYNC.md

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_ENV="${APP_ENV:-development}"
LOCK_FILE="${INVENTORY_SYNC_LOCK:-/tmp/em-tools-inventory-sync.lock}"
LOG_DIR="${LOG_DIR:-$ROOT/log}"
BUNDLE="${EM_TOOLS_BUNDLE:-bundle}"

mkdir -p "$LOG_DIR"

usage() {
  cat <<EOF
Usage: $0 [--data] [settings.yml]

  Runs: bundle exec bin/em-tools inventory sync [config]

  Env:
    APP_ENV              settings.yml section (default: development)
    INVENTORY_SYNC_LOCK  flock lock path (default: /tmp/em-tools-inventory-sync.lock)
    LOG_DIR              default: $ROOT/log
    EM_TOOLS_BUNDLE      absolute path to bundle (cron/rbenv)
    SKIP_FLOCK=1         do not skip overlapping runs

  Cron example:
    30 3 * * * $ROOT/scripts/inventory-sync.sh >> $LOG_DIR/inventory-sync.log 2>&1
EOF
}

EXTRA=()
SETTINGS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --data)
      EXTRA+=(--data)
      shift
      ;;
    *)
      SETTINGS="$1"
      shift
      ;;
  esac
done

run_sync() {
  export APP_ENV
  echo "[inventory-sync] start=$(date -u +"%Y-%m-%dT%H:%M:%SZ") app_env=${APP_ENV} root=${ROOT}"
  if [[ -n "$SETTINGS" ]]; then
    "$BUNDLE" exec bin/em-tools inventory sync "${EXTRA[@]}" "$SETTINGS"
  else
    "$BUNDLE" exec bin/em-tools inventory sync "${EXTRA[@]}"
  fi
  echo "[inventory-sync] done=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

if [[ "${SKIP_FLOCK:-}" == "1" ]]; then
  run_sync
else
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "[inventory-sync] skip: another run holds lock ($LOCK_FILE)" >&2
    exit 0
  fi
  run_sync
fi
