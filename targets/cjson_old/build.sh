#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/targets/cjson_old/src/cjson"
OUT="$ROOT/targets/cjson_old/out"

source "$ROOT/scripts/diagnostics_env.sh"
fuzzpipe_setup_diagnostics_env

mkdir -p "$OUT"

CJSON_OBJ="$OUT/cJSON.o"
HARNESS_OBJ="$OUT/harness.o"
FUZZER_BIN="$OUT/cjson_old_fuzzer"

COMMON_FLAGS=(
  -O1
  -g
  -fno-omit-frame-pointer
  -fno-optimize-sibling-calls
)

SAN_FLAGS=(
  "-fsanitize=${FUZZPIPE_SANITIZERS}"
)

FUZZ_COV_FLAGS=(
  -fsanitize=fuzzer-no-link
)

echo "[+] Build root: $ROOT"
echo "[+] Source dir: $SRC"
echo "[+] Output dir: $OUT"
echo "[+] Sanitizers: $FUZZPIPE_SANITIZERS"

echo "[+] Compiling cJSON.c as C"
clang \
  -I"$SRC" \
  "${COMMON_FLAGS[@]}" \
  "${SAN_FLAGS[@]}" \
  "${FUZZ_COV_FLAGS[@]}" \
  -c "$SRC/cJSON.c" \
  -o "$CJSON_OBJ"

echo "[+] Compiling harness.cpp as C++"
clang++ \
  -I"$SRC" \
  "${COMMON_FLAGS[@]}" \
  "${SAN_FLAGS[@]}" \
  "${FUZZ_COV_FLAGS[@]}" \
  -c "$ROOT/targets/cjson_old/harness.cpp" \
  -o "$HARNESS_OBJ"

echo "[+] Linking fuzzer"
clang++ \
  "${COMMON_FLAGS[@]}" \
  "${SAN_FLAGS[@]}" \
  -fsanitize=fuzzer \
  "$HARNESS_OBJ" \
  "$CJSON_OBJ" \
  -o "$FUZZER_BIN"

echo "[+] Built: $FUZZER_BIN"
