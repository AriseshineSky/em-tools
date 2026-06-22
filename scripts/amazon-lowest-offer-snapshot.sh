#!/usr/bin/env bash
# Amazon lowest-offer daily snapshot: GCS seeds + coverage publish.
#
# Usage:
#   ./scripts/amazon-lowest-offer-snapshot.sh
#   ./scripts/amazon-lowest-offer-snapshot.sh de us
#
# Crontab (daily 04:00):
#   0 4 * * * /home/sky/src/em-tools/scripts/amazon-lowest-offer-snapshot.sh >> /home/sky/src/em-tools/log/em-tools.lowest-offer.log 2>&1
#
# See docs/LOWEST_OFFER_COVERAGE.md

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOG_DIR="${LOG_DIR:-$ROOT/log}"
LOCK_FILE="${LOWEST_OFFER_LOCK:-/tmp/em-tools-amazon-lowest-offer.lock}"
BUNDLE="${EM_TOOLS_BUNDLE:-bundle}"

mkdir -p "$LOG_DIR" tmp

usage() {
  cat <<EOF
Usage: $0 [marketplace ...]

  Runs: bundle exec bin/em-tools amazon coverage download-and-publish [marketplaces]

  Env:
    EM_TOOLS_BUNDLE   absolute path to bundle (required for cron/rbenv)
    LOG_DIR           default: $ROOT/log
    LOWEST_OFFER_LOCK flock lock path (default: /tmp/em-tools-amazon-lowest-offer.lock)
    SKIP_FLOCK=1      run even if another instance holds the lock

  Crontab example:
    0 4 * * * $ROOT/scripts/amazon-lowest-offer-snapshot.sh >> $LOG_DIR/em-tools.lowest-offer.log 2>&1
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
  echo "[amazon-lowest-offer] start=$(date -u +"%Y-%m-%dT%H:%M:%SZ") root=${ROOT}"
  "$BUNDLE" exec bin/em-tools amazon coverage download-and-publish "$@"
  echo "[amazon-lowest-offer] done=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

if [[ "${SKIP_FLOCK:-}" == "1" ]]; then
  run_snapshot "$@"
else
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "[amazon-lowest-offer] skip: another run holds lock ($LOCK_FILE)" >&2
    exit 0
  fi
  run_snapshot "$@"
fi
