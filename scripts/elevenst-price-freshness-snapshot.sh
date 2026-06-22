#!/usr/bin/env bash
# Daily 11ST price freshness snapshot: em_inventory (source=11ST) vs user1_kr_products (elevenst).
#
# Usage:
#   ./scripts/elevenst-price-freshness-snapshot.sh
#   ./scripts/elevenst-price-freshness-snapshot.sh --threshold-days 14
#
# Cron (daily at 05:30):
#   30 5 * * * EM_TOOLS_BUNDLE=/home/sky/.rbenv/shims/bundle /home/sky/src/em-tools/scripts/elevenst-price-freshness-snapshot.sh >> /home/sky/src/em-tools/log/elevenst-price-freshness.log 2>&1
#
# Requires .env with ELASTICSEARCH_URL and DATA_ELASTICSEARCH_URL (loaded by bin/em-tools).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOG_DIR="${LOG_DIR:-$ROOT/log}"
LOCK_FILE="${ELEVENST_PRICE_FRESHNESS_LOCK:-/tmp/em-tools-elevenst-price-freshness.lock}"
BUNDLE="${EM_TOOLS_BUNDLE:-bundle}"

mkdir -p "$LOG_DIR"

usage() {
  cat <<EOF
Usage: $0 [em-tools kr elevenst publish-price-freshness-snapshot options]

  Runs: bundle exec bin/em-tools kr elevenst publish-price-freshness-snapshot [options]

  Env:
    EM_TOOLS_BUNDLE              absolute path to bundle (cron/rbenv)
    LOG_DIR                      default: $ROOT/log
    ELEVENST_PRICE_FRESHNESS_LOCK flock lock path (default: /tmp/em-tools-elevenst-price-freshness.lock)
    SKIP_FLOCK=1                 do not skip overlapping runs

  Cron example:
    30 5 * * * EM_TOOLS_BUNDLE=/path/to/bundle $ROOT/scripts/elevenst-price-freshness-snapshot.sh >> $LOG_DIR/elevenst-price-freshness.log 2>&1
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

run_snapshot() {
  echo "[elevenst-price-freshness] start=$(date -u +"%Y-%m-%dT%H:%M:%SZ") root=${ROOT}"
  "$BUNDLE" exec bin/em-tools kr elevenst publish-price-freshness-snapshot "$@"
  echo "[elevenst-price-freshness] done=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

if [[ "${SKIP_FLOCK:-}" == "1" ]]; then
  run_snapshot "$@"
else
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "[elevenst-price-freshness] skip: another run holds lock ($LOCK_FILE)" >&2
    exit 0
  fi
  run_snapshot "$@"
fi
