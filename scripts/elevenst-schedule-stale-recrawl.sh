#!/usr/bin/env bash
# Schedule Scrapyd elevenst recrawl for stale/missing 11ST inventory products.
#
# Usage:
#   ./scripts/elevenst-schedule-stale-recrawl.sh
#   ./scripts/elevenst-schedule-stale-recrawl.sh --dry-run
#   ./scripts/elevenst-schedule-stale-recrawl.sh --stale-days 7 -n 500
#
# Prefer the systemd queue keeper (continuous top-up):
#   systemctl enable --now em-tools-elevenst-recrawl-keeper.service
# One-shot / manual still works:
#   ./scripts/elevenst-schedule-stale-recrawl.sh -n 500

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOG_DIR="${LOG_DIR:-$ROOT/log}"
LOCK_FILE="${ELEVENST_RECRAWL_LOCK:-/tmp/em-tools-elevenst-recrawl.lock}"
BUNDLE="${EM_TOOLS_BUNDLE:-bundle}"

mkdir -p "$LOG_DIR"

usage() {
  cat <<EOF
Usage: $0 [em-tools kr elevenst schedule-stale-recrawl options]

  Runs: bundle exec bin/em-tools kr elevenst schedule-stale-recrawl [options]

  Env:
    DATA_ELASTICSEARCH_URL         em_inventory + user1_kr_products cluster
    SCRAPYD_URL / SCRAPYD_PROJECT  Scrapyd API (e.g. http://35.225.68.77:6800)
    SCRAPYD_USERNAME / SCRAPYD_PASSWORD
    ELEVENST_RECRAWL_STALE_DAYS     default 7
    ELEVENST_RECRAWL_BATCH_SIZE    URLs per Scrapyd job (default 25)
    ELEVENST_RECRAWL_MAX_URLS      cap per run (default 500 when set in .env)
    EM_TOOLS_BUNDLE                absolute path to bundle (cron/rbenv)
    ELEVENST_RECRAWL_LOCK          flock lock path
    SKIP_FLOCK=1                   do not skip overlapping runs
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

run_recrawl() {
  echo "[elevenst-recrawl] start=$(date -u +"%Y-%m-%dT%H:%M:%SZ") root=${ROOT}"
  "$BUNDLE" exec bin/em-tools kr elevenst schedule-stale-recrawl "$@"
  echo "[elevenst-recrawl] done=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

# When cron invokes this script with no CLI args, apply .env caps so each run
# schedules a bounded batch instead of the full backlog at once.
default_cli_args() {
  if (($# > 0)); then
    printf '%s\n' "$@"
    return
  fi

  args=(--stale-days "${ELEVENST_RECRAWL_STALE_DAYS:-7}")
  max_urls="${ELEVENST_RECRAWL_MAX_URLS:-500}"
  if [[ -n "${max_urls}" && "${max_urls}" != "0" ]]; then
    args+=(-n "${max_urls}")
  fi
  if [[ -n "${ELEVENST_RECRAWL_BATCH_SIZE:-}" ]]; then
    args+=(--batch-size "${ELEVENST_RECRAWL_BATCH_SIZE}")
  fi
  printf '%s\n' "${args[@]}"
}

if [[ "${SKIP_FLOCK:-}" == "1" ]]; then
  mapfile -t cli_args < <(default_cli_args "$@")
  run_recrawl "${cli_args[@]}"
else
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "[elevenst-recrawl] skip: another run holds lock ($LOCK_FILE)" >&2
    exit 0
  fi
  mapfile -t cli_args < <(default_cli_args "$@")
  run_recrawl "${cli_args[@]}"
fi
