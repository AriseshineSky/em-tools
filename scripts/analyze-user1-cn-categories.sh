#!/usr/bin/env bash
# Count user1_cn_products category tree (level1 / level1>level2) for inspireuplift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec bundle exec bin/em-tools ebay products analyze-user1-cn-categories "$@"
