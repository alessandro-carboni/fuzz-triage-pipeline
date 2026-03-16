#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
CRASH_PATH="${2:-}"

if [ -z "$TARGET" ] || [ -z "$CRASH_PATH" ]; then
  echo "Usage: triage/repro.sh <target> <crash_path>"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -f "$CRASH_PATH" ]; then
  echo "Crash file not found: $CRASH_PATH"
  exit 1
fi

RUN_ID="$(date +%Y-%m-%d_%H%M%S)"
REPRO_DIR="$ROOT/artifacts/repros/$TARGET/$RUN_ID"
mkdir -p "$REPRO_DIR"

LOG_FILE="$REPRO_DIR/repro.log"
META_FILE="$REPRO_DIR/repro_meta.json"

FUZZER=""
if [ "$TARGET" = "cjson" ]; then
  FUZZER="$ROOT/targets/cjson/out/cjson_fuzzer"
else
  echo "Unknown target: $TARGET"
  exit 1
fi

if [ ! -x "$FUZZER" ]; then
  echo "Fuzzer binary not found or not executable: $FUZZER"
  echo "Hint: run fuzz build first to produce the binary."
  exit 1
fi

cat > "$META_FILE" <<EOF
{
  "target": "$TARGET",
  "repro_id": "$RUN_ID",
  "timestamp": "$(date -Iseconds)",
  "crash_path": "$CRASH_PATH",
  "fuzzer_path": "$FUZZER"
}
EOF

echo "[+] Reproducing crash..." | tee -a "$LOG_FILE"
echo "[+] Fuzzer: $FUZZER" | tee -a "$LOG_FILE"
echo "[+] Crash: $CRASH_PATH" | tee -a "$LOG_FILE"
echo "[+] Repro dir: $REPRO_DIR" | tee -a "$LOG_FILE"

export ASAN_SYMBOLIZER_PATH="${ASAN_SYMBOLIZER_PATH:-$(command -v llvm-symbolizer || true)}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=1}"
export ASAN_OPTIONS="${ASAN_OPTIONS:-symbolize=1:detect_leaks=0:abort_on_error=1}"
export FUZZPIPE_DEMO_CRASH="${FUZZPIPE_DEMO_CRASH:-0}"

echo "[+] ASAN_SYMBOLIZER_PATH=${ASAN_SYMBOLIZER_PATH:-unset}" | tee -a "$LOG_FILE"
echo "[+] UBSAN_OPTIONS=$UBSAN_OPTIONS" | tee -a "$LOG_FILE"
echo "[+] ASAN_OPTIONS=$ASAN_OPTIONS" | tee -a "$LOG_FILE"
echo "[+] FUZZPIPE_DEMO_CRASH=$FUZZPIPE_DEMO_CRASH" | tee -a "$LOG_FILE"

"$FUZZER" "$CRASH_PATH" 2>&1 | tee -a "$LOG_FILE" || true

echo "[+] Saved repro log to: $LOG_FILE"
echo "[+] Saved repro meta to: $META_FILE"