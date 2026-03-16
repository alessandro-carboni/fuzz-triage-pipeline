#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
CRASH_PATH="${2:-}"

if [ -z "$TARGET" ] || [ -z "$CRASH_PATH" ]; then
  echo "Usage: triage/repro.sh <target> <crash_path>"
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

REPRO_ID="$(date +%Y-%m-%d_%H%M%S)"
REPRO_DIR="$ROOT/artifacts/repros/$TARGET/$REPRO_ID"
mkdir -p "$REPRO_DIR"

LOG_FILE="$REPRO_DIR/repro.log"
META_FILE="$REPRO_DIR/repro_meta.json"

FUZZER="$(fuzzpipe_target_fuzzer_path "$ROOT" "$TARGET")"

if [ ! -x "$FUZZER" ]; then
  echo "Fuzzer binary not found or not executable: $FUZZER"
  echo "Hint: run fuzz build first to produce the binary."
  exit 1
fi

CRASH_FILE="$(basename "$CRASH_PATH")"
RUN_DIR="$(dirname "$(dirname "$CRASH_PATH")")"
RUN_ID="$(basename "$RUN_DIR")"
RUN_META="$RUN_DIR/meta.json"

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

echo "[+] Reproducing crash..." | tee -a "$LOG_FILE"
echo "[+] Fuzzer: $FUZZER" | tee -a "$LOG_FILE"
echo "[+] Crash: $CRASH_PATH" | tee -a "$LOG_FILE"
echo "[+] Crash file: $CRASH_FILE" | tee -a "$LOG_FILE"
echo "[+] Run id: $RUN_ID" | tee -a "$LOG_FILE"
echo "[+] Repro dir: $REPRO_DIR" | tee -a "$LOG_FILE"
fuzzpipe_print_diagnostics_env | tee -a "$LOG_FILE"
echo "[+] FUZZPIPE_DEMO_CRASH=$FUZZPIPE_DEMO_CRASH" | tee -a "$LOG_FILE"

set +e
"$FUZZER" "$CRASH_PATH" 2>&1 | tee -a "$LOG_FILE"
FUZZ_EXIT=${PIPESTATUS[0]}
set -e

echo "[+] Fuzzer exit code: $FUZZ_EXIT" | tee -a "$LOG_FILE"

REPRO_STATUS="not-crashed"
if grep -qiE "ERROR: AddressSanitizer:|runtime error:|ERROR: libFuzzer:|SUMMARY: AddressSanitizer:|SUMMARY: libFuzzer:" "$LOG_FILE"; then
  REPRO_STATUS="crashed"
elif grep -qi "timeout" "$LOG_FILE"; then
  REPRO_STATUS="timeout"
elif [ "$FUZZ_EXIT" -ne 0 ]; then
  REPRO_STATUS="nonzero-exit"
fi

echo "[+] Repro status: $REPRO_STATUS" | tee -a "$LOG_FILE"

cat > "$META_FILE" <<EOF
{
  "target": "$TARGET",
  "repro_id": "$REPRO_ID",
  "timestamp": "$(date -Iseconds)",
  "run_id": "$RUN_ID",
  "crash_file": "$CRASH_FILE",
  "crash_path": "$CRASH_PATH",
  "fuzzer_path": "$FUZZER",
  "exit_code": $FUZZ_EXIT,
  "repro_status": "$REPRO_STATUS",
  "diagnostics": {
    "sanitizers": "${FUZZPIPE_SANITIZERS}",
    "asan_symbolizer_path": "${ASAN_SYMBOLIZER_PATH:-}",
    "asan_options": "${ASAN_OPTIONS}",
    "ubsan_options": "${UBSAN_OPTIONS}"
  },
  "demo_crash": "${FUZZPIPE_DEMO_CRASH}"
}
EOF

echo "[+] Saved repro log to: $LOG_FILE"
echo "[+] Saved repro meta to: $META_FILE"
