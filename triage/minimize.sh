#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
CRASH_PATH="${2:-}"

if [ -z "$TARGET" ] || [ -z "$CRASH_PATH" ]; then
  echo "Usage: triage/minimize.sh <target> <crash_path>"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

source "$ROOT/scripts/diagnostics_env.sh"
source "$ROOT/scripts/target_common.sh"
fuzzpipe_setup_diagnostics_env

fuzzpipe_assert_target_exists "$ROOT" "$TARGET"

if [ ! -f "$CRASH_PATH" ]; then
  echo "Crash file not found: $CRASH_PATH"
  exit 1
fi

MINIMIZE_ID="$(date +%Y-%m-%d_%H%M%S)"
MIN_DIR="$ROOT/artifacts/minimized/$TARGET/$MINIMIZE_ID"
mkdir -p "$MIN_DIR"

LOG_FILE="$MIN_DIR/minimize.log"
META_FILE="$MIN_DIR/minimize_meta.json"

FUZZER="$(fuzzpipe_target_fuzzer_path "$ROOT" "$TARGET")"

if [ ! -x "$FUZZER" ]; then
  echo "Fuzzer binary not found or not executable: $FUZZER"
  echo "Hint: build the target first."
  exit 1
fi

CRASH_FILE="$(basename "$CRASH_PATH")"
RUN_DIR="$(dirname "$(dirname "$CRASH_PATH")")"
RUN_ID="$(basename "$RUN_DIR")"
RUN_META="$RUN_DIR/meta.json"

MIN_OUTPUT="$MIN_DIR/minimized-$CRASH_FILE"

ORIGINAL_SIZE="$(wc -c < "$CRASH_PATH" | tr -d '[:space:]')"
MINIMIZE_MAX_TOTAL_TIME="${MINIMIZE_MAX_TOTAL_TIME:-20}"

# Default: real mode
export FUZZPIPE_DEMO_CRASH=0

# If this crash belongs to a demo run, re-enable demo mode
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
echo "[+] Crash file: $CRASH_FILE" | tee -a "$LOG_FILE"
echo "[+] Run id: $RUN_ID" | tee -a "$LOG_FILE"
echo "[+] Output file: $MIN_OUTPUT" | tee -a "$LOG_FILE"
echo "[+] Original size: $ORIGINAL_SIZE" | tee -a "$LOG_FILE"
echo "[+] MINIMIZE_MAX_TOTAL_TIME=$MINIMIZE_MAX_TOTAL_TIME" | tee -a "$LOG_FILE"
fuzzpipe_print_diagnostics_env | tee -a "$LOG_FILE"
echo "[+] FUZZPIPE_DEMO_CRASH=$FUZZPIPE_DEMO_CRASH" | tee -a "$LOG_FILE"

set +e
"$FUZZER" \
  -minimize_crash=1 \
  -max_total_time="$MINIMIZE_MAX_TOTAL_TIME" \
  -exact_artifact_path="$MIN_OUTPUT" \
  "$CRASH_PATH" 2>&1 | tee -a "$LOG_FILE"
FUZZ_EXIT=${PIPESTATUS[0]}
set -e

echo "[+] Fuzzer exit code: $FUZZ_EXIT" | tee -a "$LOG_FILE"

if [ ! -f "$MIN_OUTPUT" ]; then
  MINIMIZE_STATUS="failed"
  cat > "$META_FILE" <<EOF
{
  "target": "$TARGET",
  "minimize_id": "$MINIMIZE_ID",
  "timestamp": "$(date -Iseconds)",
  "run_id": "$RUN_ID",
  "crash_file": "$CRASH_FILE",
  "crash_path": "$CRASH_PATH",
  "minimized_path": null,
  "fuzzer_path": "$FUZZER",
  "original_size": $ORIGINAL_SIZE,
  "minimized_size": null,
  "reduction_percent": null,
  "max_total_time": $MINIMIZE_MAX_TOTAL_TIME,
  "exit_code": $FUZZ_EXIT,
  "minimize_status": "$MINIMIZE_STATUS",
  "diagnostics": {
    "sanitizers": "${FUZZPIPE_SANITIZERS}",
    "asan_symbolizer_path": "${ASAN_SYMBOLIZER_PATH:-}",
    "asan_options": "${ASAN_OPTIONS}",
    "ubsan_options": "${UBSAN_OPTIONS}"
  },
  "demo_crash": "${FUZZPIPE_DEMO_CRASH}"
}
EOF
  echo "[-] Minimized output was not produced." | tee -a "$LOG_FILE"
  echo "[+] Saved minimize meta to: $META_FILE"
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

MINIMIZE_STATUS="minimized"

cat > "$META_FILE" <<EOF
{
  "target": "$TARGET",
  "minimize_id": "$MINIMIZE_ID",
  "timestamp": "$(date -Iseconds)",
  "run_id": "$RUN_ID",
  "crash_file": "$CRASH_FILE",
  "crash_path": "$CRASH_PATH",
  "minimized_path": "$MIN_OUTPUT",
  "fuzzer_path": "$FUZZER",
  "original_size": $ORIGINAL_SIZE,
  "minimized_size": $MIN_SIZE,
  "reduction_percent": $REDUCTION_PERCENT,
  "max_total_time": $MINIMIZE_MAX_TOTAL_TIME,
  "exit_code": $FUZZ_EXIT,
  "minimize_status": "$MINIMIZE_STATUS",
  "diagnostics": {
    "sanitizers": "${FUZZPIPE_SANITIZERS}",
    "asan_symbolizer_path": "${ASAN_SYMBOLIZER_PATH:-}",
    "asan_options": "${ASAN_OPTIONS}",
    "ubsan_options": "${UBSAN_OPTIONS}"
  },
  "demo_crash": "${FUZZPIPE_DEMO_CRASH}"
}
EOF

echo "[+] Minimize status: $MINIMIZE_STATUS" | tee -a "$LOG_FILE"
echo "[+] Saved minimize log to: $LOG_FILE"
echo "[+] Saved minimize meta to: $META_FILE"
echo "[+] Minimized file: $MIN_OUTPUT"
