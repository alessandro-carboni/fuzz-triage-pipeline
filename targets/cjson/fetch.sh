#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/scripts/target_fetch_common.sh"

TARGET_REF="${TARGET_REF:-v1.7.17}"
REPO_URL="https://github.com/DaveGamble/cJSON.git"

fuzzpipe_fetch_git_target "$ROOT" "cjson" "$REPO_URL" "cjson" "$TARGET_REF"
