#!/usr/bin/env bash
# Incremental sync: user1_ebay_products (DATA_ELASTICSEARCH_URL) -> ebay_us_products (ELASTICSEARCH_URL).
#
# Usage:
#   ./scripts/ebay-sync-user1-products.sh
#   ./scripts/ebay-sync-user1-products.sh --since-hours 6
#   ./scripts/ebay-sync-user1-products.sh --full --skip-missing --dry-run
#
# Cron (twice daily UTC at 02:25 / 14:25, last 24h):
#   25 2,14 * * * EM_TOOLS_BUNDLE=/home/Admin/.rbenv/shims/bundle /home/Admin/src/em-tools/scripts/ebay-sync-user1-products.sh --since-hours 24 >> /home/Admin/src/em-tools/log/ebay-sync-user1-products.log 2>&1
#
# Requires .env with ELASTICSEARCH_URL and DATA_ELASTICSEARCH_URL (loaded by bin/em-tools).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOG_DIR="${LOG_DIR:-$ROOT/log}"
LOCK_FILE="${EBAY_PRODUCT_SYNC_LOCK:-/tmp/em-tools-ebay-sync-user1-products.lock}"
BUNDLE="${EM_TOOLS_BUNDLE:-bundle}"

mkdir -p "$LOG_DIR"

usage() {
  cat <<EOF
Usage: $0 [em-tools ebay products sync-user1 options]

  Runs: bundle exec bin/em-tools ebay products sync-user1 [options]

  Env:
    EM_TOOLS_BUNDLE       absolute path to bundle (cron/rbenv)
    LOG_DIR               default: $ROOT/log
    EBAY_PRODUCT_SYNC_LOCK flock lock path (default: /tmp/em-tools-ebay-sync-user1-products.lock)
    SKIP_FLOCK=1          do not skip overlapping runs

  Cron example:
    25 2,14 * * * EM_TOOLS_BUNDLE=/path/to/bundle $ROOT/scripts/ebay-sync-user1-products.sh --since-hours 24 >> $LOG_DIR/ebay-sync-user1-products.log 2>&1
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

run_sync() {
  echo "[ebay-sync-user1-products] start=$(date -u +"%Y-%m-%dT%H:%M:%SZ") root=${ROOT}"
  "$BUNDLE" exec bin/em-tools ebay products sync-user1 "$@"
  echo "[ebay-sync-user1-products] done=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

if [[ "${SKIP_FLOCK:-}" == "1" ]]; then
  run_sync "$@"
else
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "[ebay-sync-user1-products] skip: another run holds lock ($LOCK_FILE)" >&2
    exit 0
  fi
  run_sync "$@"
fi
