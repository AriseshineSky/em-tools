#!/usr/bin/env bash
# Sync one GCS inventory CSV into em_inventory (wrapper around sync-from-gcs).
#
# Usage:
#   ./scripts/inventory-sync-from-gcs.sh gs://em-bucket/AMZ_DE-Inv.csv
#   INVENTORY_FEED_ID=AMZ_DE ./scripts/inventory-sync-from-gcs.sh gs://em-bucket/AMZ_DE-Inv.csv
#   ./scripts/inventory-sync-from-gcs.sh gs://em-bucket/AMZ_DE-Inv.csv --prune
#
# If INVENTORY_FEED_ID is unset, infers AMZ_{MP} from filenames like AMZ_DE-Inv.csv.
#
# See docs/INVENTORY_SYNC.md

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE="${EM_TOOLS_BUNDLE:-bundle}"
PRUNE="${INVENTORY_PRUNE_OBSOLETE:-}"

usage() {
  cat <<EOF
Usage: $0 <gs://bucket/path.csv> [--prune]

  Env:
    INVENTORY_FEED_ID         inventory_feed for prune (auto: AMZ_DE from AMZ_DE-Inv.csv)
    INVENTORY_PRUNE_OBSOLETE  set to 1 to delete stale docs (same feed)
    EM_TOOLS_BUNDLE           absolute path to bundle
EOF
}

GS_URI=""
EXTRA=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --prune)
      PRUNE=1
      shift
      ;;
    gs://*)
      GS_URI="$1"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$GS_URI" ]]; then
  GS_URI="${INVENTORY_GS_URI:-}"
fi

if [[ -z "$GS_URI" ]]; then
  echo "Usage: $0 gs://bucket/path.csv [--prune]" >&2
  exit 1
fi

if [[ -z "${INVENTORY_FEED_ID:-}" ]]; then
  base="$(basename "$GS_URI")"
  if [[ "$base" =~ ^AMZ_([A-Za-z]{2})-Inv\.csv$ ]]; then
    export INVENTORY_FEED_ID="AMZ_${BASH_REMATCH[1]^^}"
    echo "[inventory-sync-from-gcs] inferred INVENTORY_FEED_ID=${INVENTORY_FEED_ID}" >&2
  fi
fi

if [[ "$PRUNE" == "1" ]]; then
  export INVENTORY_PRUNE_OBSOLETE=1
fi

exec "$BUNDLE" exec bin/em-tools inventory sync-from-gcs "$GS_URI" "${EXTRA[@]}"
