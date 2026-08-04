#!/usr/bin/env bash
# Incremental sync: user1_de_products source=docmorris (DATA_ELASTICSEARCH_URL)
#                 -> catalog_products (ELASTICSEARCH_URL), slim projection.
#
# Usage:
#   ./scripts/catalog-sync-docmorris-products.sh
#   ./scripts/catalog-sync-docmorris-products.sh --since-hours 36
#   ./scripts/catalog-sync-docmorris-products.sh --full --dry-run
#
# Cron (daily, overlapping 36h window):
#   40 3 * * * EM_TOOLS_BUNDLE=… …/scripts/catalog-sync-docmorris-products.sh --since-hours 36 >> …/log/catalog-sync-docmorris-products.log 2>&1
#
# Requires .env with ELASTICSEARCH_URL and DATA_ELASTICSEARCH_URL.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOG_DIR="${LOG_DIR:-$ROOT/log}"
LOCK_FILE="${CATALOG_DOCMORRIS_SYNC_LOCK:-/tmp/em-tools-catalog-sync-docmorris-products.lock}"
BUNDLE="${EM_TOOLS_BUNDLE:-bundle}"

mkdir -p "$LOG_DIR"

usage() {
  cat <<EOF
Usage: $0 [em-tools catalog products sync-docmorris options]

  Runs: bundle exec bin/em-tools catalog products sync-docmorris [options]

  Env:
    EM_TOOLS_BUNDLE                 absolute path to bundle (cron/rbenv)
    LOG_DIR                         default: $ROOT/log
    CATALOG_DOCMORRIS_SYNC_LOCK     flock lock path
    SKIP_FLOCK=1                    do not skip overlapping runs

  Cron example:
    40 3 * * * EM_TOOLS_BUNDLE=/path/to/bundle $ROOT/scripts/catalog-sync-docmorris-products.sh --since-hours 36 >> $LOG_DIR/catalog-sync-docmorris-products.log 2>&1
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
  echo "[catalog-sync-docmorris-products] start=$(date -u +"%Y-%m-%dT%H:%M:%SZ") root=${ROOT}"
  "$BUNDLE" exec bin/em-tools catalog products sync-docmorris "$@"
  echo "[catalog-sync-docmorris-products] done=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

if [[ "${SKIP_FLOCK:-}" == "1" ]]; then
  run_sync "$@"
else
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "[catalog-sync-docmorris-products] skip: another run holds lock ($LOCK_FILE)" >&2
    exit 0
  fi
  run_sync "$@"
fi
