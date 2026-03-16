#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-cjson}"
MODE="${2:-normal}"   # normal | demo-crash

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

source "$ROOT/scripts/diagnostics_env.sh"
fuzzpipe_setup_diagnostics_env

# Unique run id
RUN_ID="$(date +%Y-%m-%d_%H%M%S)"

RUN_DIR="$ROOT/artifacts/runs/$TARGET/$RUN_ID"
CRASH_DIR="$RUN_DIR/crashes"
CORPUS_DIR="$RUN_DIR/corpus"
LOG_FILE="$RUN_DIR/run.log"
META_FILE="$RUN_DIR/meta.json"

mkdir -p "$CRASH_DIR" "$CORPUS_DIR"

# Common fuzzing knobs (can be overridden via env)
MAX_TOTAL_TIME="${MAX_TOTAL_TIME:-0}"   # 0 = run until Ctrl+C
MAX_LEN="${MAX_LEN:-4096}"
TIMEOUT="${TIMEOUT:-2}"

write_meta() {
  local target_version="$1"
  cat > "$META_FILE" <<EOF
{
  "target": "$TARGET",
  "mode": "$MODE",
  "run_id": "$RUN_ID",
  "timestamp": "$(date -Iseconds)",
  "docker_image": "${DOCKER_IMAGE_TAG:-unknown}",
  "target_version": "$target_version",
  "target_ref": "${TARGET_REF:-master}",
  "fuzzer": "libFuzzer",
  "diagnostics": {
    "sanitizers": "${FUZZPIPE_SANITIZERS}",
    "asan_symbolizer_path": "${ASAN_SYMBOLIZER_PATH:-}",
    "asan_options": "${ASAN_OPTIONS}",
    "ubsan_options": "${UBSAN_OPTIONS}"
  },
  "args": {
    "max_total_time": $MAX_TOTAL_TIME,
    "max_len": $MAX_LEN,
    "timeout": $TIMEOUT
  }
}
EOF
}

if [ "$TARGET" = "cjson" ] || [ "$TARGET" = "cjson_old" ]; then
  echo "[+] Run dir: $RUN_DIR" | tee -a "$LOG_FILE"

  echo "[+] Fetching target sources ($TARGET)" | tee -a "$LOG_FILE"
  bash "$ROOT/targets/$TARGET/fetch.sh" 2>&1 | tee -a "$LOG_FILE"

  TARGET_REPO="$ROOT/targets/$TARGET/src/cjson"
  TARGET_VERSION="unknown"
  if [ -d "$TARGET_REPO/.git" ]; then
    TARGET_VERSION="$(git -C "$TARGET_REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  fi

  echo "[+] Building target fuzzer" | tee -a "$LOG_FILE"
  bash "$ROOT/targets/$TARGET/build.sh" 2>&1 | tee -a "$LOG_FILE"

  write_meta "$TARGET_VERSION"

  if [ "$TARGET" = "cjson" ]; then
    FUZZER="$ROOT/targets/cjson/out/cjson_fuzzer"
  elif [ "$TARGET" = "cjson_old" ]; then
    FUZZER="$ROOT/targets/cjson_old/out/cjson_old_fuzzer"
  else
    echo "[-] Unsupported target binary mapping: $TARGET" | tee -a "$LOG_FILE"
    exit 1
  fi

  if [ ! -x "$FUZZER" ]; then
    echo "[-] Fuzzer binary not found or not executable: $FUZZER" | tee -a "$LOG_FILE"
    exit 1
  fi

  # Default: real mode
  export FUZZPIPE_DEMO_CRASH=0

  # Demo mode
  if [ "$MODE" = "demo-crash" ]; then
    echo "[+] DEMO CRASH enabled (FUZZPIPE_DEMO_CRASH=1)" | tee -a "$LOG_FILE"
    export FUZZPIPE_DEMO_CRASH=1

    DEMO_SEED="$ROOT/artifacts/demo/$TARGET/demo_seed.txt"
    if [ -f "$DEMO_SEED" ]; then
      cp "$DEMO_SEED" "$CORPUS_DIR/seed_CRASHME.txt"
      echo "[+] Added demo seed to corpus: seed_CRASHME.txt" | tee -a "$LOG_FILE"
    else
      echo "[-] Demo seed not found at $DEMO_SEED" | tee -a "$LOG_FILE"
    fi
  fi

  # Initial seed corpus
  SEED_DIR="$ROOT/corpus/initial/$TARGET"
  if [ -d "$SEED_DIR" ]; then
    echo "[+] Loading initial corpus from $SEED_DIR" | tee -a "$LOG_FILE"
    cp -n "$SEED_DIR"/* "$CORPUS_DIR"/ 2>/dev/null || true
  fi

  echo "[+] Running libFuzzer" | tee -a "$LOG_FILE"
  fuzzpipe_print_diagnostics_env | tee -a "$LOG_FILE"
  echo "[+] FUZZPIPE_DEMO_CRASH=$FUZZPIPE_DEMO_CRASH" | tee -a "$LOG_FILE"

  FUZZ_ARGS=(
    "-artifact_prefix=$CRASH_DIR/"
    "-max_len=$MAX_LEN"
    "-timeout=$TIMEOUT"
  )

  # Optional dictionary
  DICT_FILE="$ROOT/targets/$TARGET/dict/json.dict"
  if [ -f "$DICT_FILE" ]; then
    echo "[+] Using dictionary: $DICT_FILE" | tee -a "$LOG_FILE"
    FUZZ_ARGS+=("-dict=$DICT_FILE")
  fi

  if [ "$MAX_TOTAL_TIME" != "0" ]; then
    FUZZ_ARGS+=("-max_total_time=$MAX_TOTAL_TIME")
  fi

  "$FUZZER" "${FUZZ_ARGS[@]}" "$CORPUS_DIR" 2>&1 | tee -a "$LOG_FILE"

else
  echo "Unknown target: $TARGET"
  echo "Usage: ./fuzz/fuzz.sh cjson [normal|demo-crash]"
  exit 1
fi
