#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="yaml"
REPO_SUBDIR="libyaml"

source "$ROOT/scripts/target_build_common.sh"

fuzzpipe_build_libyaml_target "$ROOT" "$TARGET" "$REPO_SUBDIR"
