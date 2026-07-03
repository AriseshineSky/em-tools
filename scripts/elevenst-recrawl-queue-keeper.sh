#!/usr/bin/env bash
# Keep Scrapyd elevenst recrawl queue near a target depth (systemd long-running service).
#
# Polls listjobs.json; when pending+running jobs drop below target, calls
# elevenst-schedule-stale-recrawl.sh to top up from stale/missing inventory.
#
# Env (also in .env / systemd EnvironmentFile):
#   SCRAPYD_URL, SCRAPYD_PROJECT, SCRAPYD_USERNAME, SCRAPYD_PASSWORD
#   ELEVENST_RECRAWL_TARGET_JOBS       desired pending+running jobs (default 20)
#   ELEVENST_RECRAWL_BATCH_SIZE        URLs per job (default 25)
#   ELEVENST_RECRAWL_STALE_DAYS        freshness threshold (default 7)
#   ELEVENST_RECRAWL_POLL_SECONDS      loop interval (default 30)
#   ELEVENST_RECRAWL_TOP_UP_COOLDOWN_SECONDS  min gap between ES top-ups (default 120)
#   ELEVENST_RECRAWL_TOP_UP_MAX_URLS   cap URLs per top-up (default 500)
#   EM_TOOLS_BUNDLE                    absolute bundle path (rbenv)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE="${EM_TOOLS_BUNDLE:-bundle}"
SCHEDULE_SCRIPT="$ROOT/scripts/elevenst-schedule-stale-recrawl.sh"

TARGET_JOBS="${ELEVENST_RECRAWL_TARGET_JOBS:-20}"
BATCH_SIZE="${ELEVENST_RECRAWL_BATCH_SIZE:-25}"
STALE_DAYS="${ELEVENST_RECRAWL_STALE_DAYS:-7}"
POLL_SEC="${ELEVENST_RECRAWL_POLL_SECONDS:-30}"
COOLDOWN_SEC="${ELEVENST_RECRAWL_TOP_UP_COOLDOWN_SECONDS:-120}"
TOP_UP_MAX_URLS="${ELEVENST_RECRAWL_TOP_UP_MAX_URLS:-500}"

SCRAPYD_URL="${SCRAPYD_URL:-}"
SCRAPYD_PROJECT="${SCRAPYD_PROJECT:-kr_products_spider}"
SCRAPYD_USERNAME="${SCRAPYD_USERNAME:-}"
SCRAPYD_PASSWORD="${SCRAPYD_PASSWORD:-}"

log() {
  echo "[elevenst-recrawl-keeper] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"
}

scrapyd_queue_jobs() {
  local base="${SCRAPYD_URL%/}"
  if [[ -z "$base" ]]; then
    log "error: SCRAPYD_URL is not set"
    return 1
  fi

  local curl_args=(-sfS --connect-timeout 10 --max-time 30)
  if [[ -n "$SCRAPYD_USERNAME" ]]; then
    curl_args+=(-u "${SCRAPYD_USERNAME}:${SCRAPYD_PASSWORD}")
  fi

  local json
  json="$(curl "${curl_args[@]}" "${base}/listjobs.json?project=${SCRAPYD_PROJECT}")" || return 1

  read -r QUEUE_JOBS queue_pending queue_running < <(python3 -c "
import json, sys
d = json.load(sys.stdin)
pending = len(d.get('pending', []))
running = len(d.get('running', []))
print(pending + running, pending, running)
" <<<"$json")
}

top_up_queue() {
  local queue_jobs="$1"
  local jobs_needed=$((TARGET_JOBS - queue_jobs))
  if ((jobs_needed <= 0)); then
    return 0
  fi

  local urls_needed=$((jobs_needed * BATCH_SIZE))
  if ((urls_needed > TOP_UP_MAX_URLS)); then
    urls_needed="$TOP_UP_MAX_URLS"
  fi
  if ((urls_needed <= 0)); then
    return 0
  fi

  log "top-up queue=${queue_jobs}/${TARGET_JOBS} pending=${queue_pending:-?} running=${queue_running:-?} urls=${urls_needed}"
  "$SCHEDULE_SCRIPT" \
    --stale-days "$STALE_DAYS" \
    --batch-size "$BATCH_SIZE" \
    -n "$urls_needed"
}

shutdown=0
trap 'shutdown=1; log "signal received, exiting"' TERM INT

last_top_up=0
log "start target_jobs=${TARGET_JOBS} batch_size=${BATCH_SIZE} poll=${POLL_SEC}s cooldown=${COOLDOWN_SEC}s top_up_max=${TOP_UP_MAX_URLS} scrapyd=${SCRAPYD_URL} project=${SCRAPYD_PROJECT}"

while ((shutdown == 0)); do
  queue_pending=0
  queue_running=0
  if scrapyd_queue_jobs; then
    now="$(date +%s)"
    cooldown_ok=0
    if ((now - last_top_up >= COOLDOWN_SEC)); then
      cooldown_ok=1
    fi

    if ((QUEUE_JOBS < TARGET_JOBS && cooldown_ok == 1)); then
      if top_up_queue "$QUEUE_JOBS"; then
        last_top_up="$now"
      else
        log "warn: top-up failed"
      fi
    elif ((QUEUE_JOBS < TARGET_JOBS)); then
      log "queue=${QUEUE_JOBS}/${TARGET_JOBS} pending=${queue_pending} running=${queue_running} cooldown=${COOLDOWN_SEC}s"
    else
      log "queue=${QUEUE_JOBS}/${TARGET_JOBS} ok pending=${queue_pending} running=${queue_running}"
    fi
  else
    log "warn: scrapyd poll failed"
  fi

  for ((i = 0; i < POLL_SEC && shutdown == 0; i++)); do
    sleep 1
  done
done

log "stopped"
