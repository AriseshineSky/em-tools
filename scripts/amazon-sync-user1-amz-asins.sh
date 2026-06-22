#!/usr/bin/env bash
# Hourly sync: user1_amz_asins (DATA_ELASTICSEARCH_URL) -> amz_asins_<mp> (ELASTICSEARCH_URL).
#
# Usage:
#   ./scripts/amazon-sync-user1-amz-asins.sh
#   ./scripts/amazon-sync-user1-amz-asins.sh --since-hours 6
#   ./scripts/amazon-sync-user1-amz-asins.sh -m br --since-hours 2
#   ./scripts/amazon-sync-user1-amz-asins.sh --full --dry-run
#
# Cron (hourly at :15):
#   15 * * * * EM_TOOLS_BUNDLE=/home/sky/.rbenv/shims/bundle /home/sky/src/em-tools/scripts/amazon-sync-user1-amz-asins.sh --since-hours 3 >> /home/sky/src/em-tools/log/amazon-sync-user1-amz-asins.log 2>&1
#
# Requires .env with ELASTICSEARCH_URL and DATA_ELASTICSEARCH_URL (loaded by bin/em-tools).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOG_DIR="${LOG_DIR:-$ROOT/log}"
LOCK_FILE="${AMZ_ASIN_SYNC_LOCK:-/tmp/em-tools-amazon-sync-user1-amz-asins.lock}"
BUNDLE="${EM_TOOLS_BUNDLE:-bundle}"

mkdir -p "$LOG_DIR"

usage() {
  cat <<EOF
Usage: $0 [em-tools amazon asins sync-user1 options]

  Runs: bundle exec bin/em-tools amazon asins sync-user1 [options]

  Env:
    EM_TOOLS_BUNDLE    absolute path to bundle (cron/rbenv)
    LOG_DIR            default: $ROOT/log
    AMZ_ASIN_SYNC_LOCK flock lock path (default: /tmp/em-tools-amazon-sync-user1-amz-asins.lock)
    SKIP_FLOCK=1       do not skip overlapping runs

  Cron example:
    15 * * * * EM_TOOLS_BUNDLE=/path/to/bundle $ROOT/scripts/amazon-sync-user1-amz-asins.sh --since-hours 3 >> $LOG_DIR/amazon-sync-user1-amz-asins.log 2>&1
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
  echo "[amazon-sync-user1-amz-asins] start=$(date -u +"%Y-%m-%dT%H:%M:%SZ") root=${ROOT}"
  "$BUNDLE" exec bin/em-tools amazon asins sync-user1 "$@"
  echo "[amazon-sync-user1-amz-asins] done=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

if [[ "${SKIP_FLOCK:-}" == "1" ]]; then
  run_sync "$@"
else
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "[amazon-sync-user1-amz-asins] skip: another run holds lock ($LOCK_FILE)" >&2
    exit 0
  fi
  run_sync "$@"
fi
