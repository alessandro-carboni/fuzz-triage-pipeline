#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="yaml"
REPO_URL="https://github.com/yaml/libyaml.git"
REPO_SUBDIR="libyaml"

source "$ROOT/scripts/target_fetch_common.sh"

fuzzpipe_fetch_git_target "$ROOT" "$TARGET" "$REPO_URL" "$REPO_SUBDIR" "${TARGET_REF:-master}"
