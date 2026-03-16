#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DST="$ROOT/targets/cjson_old/src/cjson"

TARGET_REF="${TARGET_REF:-master}"
REPO_URL="https://github.com/DaveGamble/cJSON.git"

if [ ! -d "$DST/.git" ]; then
  echo "[+] Cloning cJSON into $DST"
  mkdir -p "$(dirname "$DST")"
  git clone "$REPO_URL" "$DST"
else
  echo "[+] cJSON already present at $DST"
fi

echo "[+] Fetching latest refs/tags"
git -C "$DST" fetch --all --tags

if [ "$TARGET_REF" = "master" ]; then
  echo "[+] Checking out target ref: master"
  git -C "$DST" checkout master
  git -C "$DST" reset --hard origin/master
else
  echo "[+] Checking out target ref: $TARGET_REF"
  git -C "$DST" checkout "$TARGET_REF"
fi

CURRENT_COMMIT="$(git -C "$DST" rev-parse --short HEAD 2>/dev/null || echo unknown)"
CURRENT_REF="$(git -C "$DST" rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"

echo "[+] cJSON ready"
echo "[+] Ref: $TARGET_REF"
echo "[+] Branch/HEAD: $CURRENT_REF"
echo "[+] Commit: $CURRENT_COMMIT"
