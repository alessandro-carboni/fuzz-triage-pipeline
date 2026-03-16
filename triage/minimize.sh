#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
CRASH_PATH="${2:-}"

if [ -z "$TARGET" ] || [ -z "$CRASH_PATH" ]; then
  echo "Usage: triage/minimize.sh <target> <crash_path>"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -f "$CRASH_PATH" ]; then
  echo "Crash file not found: $CRASH_PATH"
  exit 1
fi

MIN_ID="$(date +%Y-%m-%d_%H%M%S)"
MIN_DIR="$ROOT/artifacts/minimized/$TARGET/$MIN_ID"
mkdir -p "$MIN_DIR"

LOG_FILE="$MIN_DIR/minimize.log"
META_FILE="$MIN_DIR/minimize_meta.json"

FUZZER=""
if [ "$TARGET" = "cjson" ]; then
  FUZZER="$ROOT/targets/cjson/out/cjson_fuzzer"
else
  echo "Unknown target: $TARGET"
  exit 1
fi

if [ ! -x "$FUZZER" ]; then
  echo "Fuzzer binary not found or not executable: $FUZZER"
  echo "Hint: build the target first."
  exit 1
fi

CRASH_BASENAME="$(basename "$CRASH_PATH")"
MIN_OUTPUT="$MIN_DIR/minimized-$CRASH_BASENAME"

ORIGINAL_SIZE="$(wc -c < "$CRASH_PATH" | tr -d '[:space:]')"
MINIMIZE_MAX_TOTAL_TIME="${MINIMIZE_MAX_TOTAL_TIME:-20}"

export ASAN_SYMBOLIZER_PATH="${ASAN_SYMBOLIZER_PATH:-$(command -v llvm-symbolizer || true)}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=1}"
export ASAN_OPTIONS="${ASAN_OPTIONS:-symbolize=1:detect_leaks=0:abort_on_error=1}"

# Default: real mode
export FUZZPIPE_DEMO_CRASH=0

# If this crash belongs to a demo run, re-enable demo mode
RUN_DIR="$(dirname "$(dirname "$CRASH_PATH")")"
RUN_META="$RUN_DIR/meta.json"
if [ -f "$RUN_META" ]; then
  RUN_MODE="$(python3 - <<PY
import json
from pathlib import Path
p = Path(r"$RUN_META")
try:
    data = json.loads(p.read_text(encoding="utf-8"))
    print(str(data.get("mode", "")).strip())
except Exception:
    print("")
PY
)"
  if [ "$RUN_MODE" = "demo-crash" ]; then
    export FUZZPIPE_DEMO_CRASH=1
  fi
fi

echo "[+] Minimizing crash..." | tee -a "$LOG_FILE"
echo "[+] Fuzzer: $FUZZER" | tee -a "$LOG_FILE"
echo "[+] Input crash: $CRASH_PATH" | tee -a "$LOG_FILE"
echo "[+] Output file: $MIN_OUTPUT" | tee -a "$LOG_FILE"
echo "[+] Original size: $ORIGINAL_SIZE" | tee -a "$LOG_FILE"
echo "[+] MINIMIZE_MAX_TOTAL_TIME=$MINIMIZE_MAX_TOTAL_TIME" | tee -a "$LOG_FILE"
echo "[+] ASAN_SYMBOLIZER_PATH=${ASAN_SYMBOLIZER_PATH:-unset}" | tee -a "$LOG_FILE"
echo "[+] UBSAN_OPTIONS=$UBSAN_OPTIONS" | tee -a "$LOG_FILE"
echo "[+] ASAN_OPTIONS=$ASAN_OPTIONS" | tee -a "$LOG_FILE"
echo "[+] FUZZPIPE_DEMO_CRASH=$FUZZPIPE_DEMO_CRASH" | tee -a "$LOG_FILE"

"$FUZZER" \
  -minimize_crash=1 \
  -max_total_time="$MINIMIZE_MAX_TOTAL_TIME" \
  -exact_artifact_path="$MIN_OUTPUT" \
  "$CRASH_PATH" 2>&1 | tee -a "$LOG_FILE" || true

if [ ! -f "$MIN_OUTPUT" ]; then
  echo "[-] Minimized output was not produced." | tee -a "$LOG_FILE"
  exit 1
fi

MIN_SIZE="$(wc -c < "$MIN_OUTPUT" | tr -d '[:space:]')"

if [ "$ORIGINAL_SIZE" -gt 0 ]; then
  REDUCTION_PERCENT="$(python3 - <<PY
orig = int("$ORIGINAL_SIZE")
mini = int("$MIN_SIZE")
print(round(((orig - mini) / orig) * 100, 2))
PY
)"
else
  REDUCTION_PERCENT="0"
fi

cat > "$META_FILE" <<EOF
{
  "target": "$TARGET",
  "minimize_id": "$MIN_ID",
  "timestamp": "$(date -Iseconds)",
  "crash_path": "$CRASH_PATH",
  "minimized_path": "$MIN_OUTPUT",
  "fuzzer_path": "$FUZZER",
  "original_size": $ORIGINAL_SIZE,
  "minimized_size": $MIN_SIZE,
  "reduction_percent": $REDUCTION_PERCENT,
  "max_total_time": $MINIMIZE_MAX_TOTAL_TIME
}
EOF

echo "[+] Saved minimize log to: $LOG_FILE"
echo "[+] Saved minimize meta to: $META_FILE"
echo "[+] Minimized file: $MIN_OUTPUT"