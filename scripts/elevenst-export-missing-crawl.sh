#!/usr/bin/env bash
# Export 11ST inventory rows missing from user1_kr_products; optionally schedule Scrapyd.
#
# Usage:
#   ./scripts/elevenst-export-missing-crawl.sh -o log/elevenst-missing.tsv
#   ./scripts/elevenst-export-missing-crawl.sh -o log/elevenst-missing.tsv --schedule
#
# Read-only ES: set DATA_ELASTICSEARCH_URL to emuser1 (see .env.example).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE="${EM_TOOLS_BUNDLE:-bundle}"
LOG_DIR="${LOG_DIR:-$ROOT/log}"
mkdir -p "$LOG_DIR"

exec "$BUNDLE" exec bin/em-tools kr elevenst export-missing-crawl "$@"
