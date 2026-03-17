#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-cjson}"
MODE="${2:-normal}"   # normal | demo-crash

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

source "$ROOT/scripts/diagnostics_env.sh"
source "$ROOT/scripts/target_common.sh"
fuzzpipe_setup_diagnostics_env

fuzzpipe_assert_target_exists "$ROOT" "$TARGET"

# Unique run id
RUN_ID="$(date +%Y-%m-%d_%H%M%S)"

RUN_DIR="$ROOT/artifacts/runs/$TARGET/$RUN_ID"
CRASH_DIR="$RUN_DIR/crashes"
CORPUS_DIR="$RUN_DIR/corpus"
LOG_FILE="$RUN_DIR/run.log"
META_FILE="$RUN_DIR/meta.json"
COVERAGE_DIR="$(fuzzpipe_target_coverage_dir "$ROOT" "$TARGET" "$RUN_ID")"

mkdir -p "$CRASH_DIR" "$CORPUS_DIR"

if [[ "${FUZZPIPE_ENABLE_COVERAGE:-0}" == "1" ]]; then
  mkdir -p "$COVERAGE_DIR"
fi

# Common fuzzing knobs (can be overridden via env)
MAX_TOTAL_TIME="${MAX_TOTAL_TIME:-0}"   # 0 = run until Ctrl+C
MAX_LEN="${MAX_LEN:-4096}"
TIMEOUT="${TIMEOUT:-2}"

write_meta() {
  local target_version="$1"
  local effective_target_ref
  local target_family
  local target_source_kind

  effective_target_ref="${TARGET_REF:-$(fuzzpipe_target_default_ref "$TARGET")}"
  target_family="$(fuzzpipe_target_family "$TARGET")"
  target_source_kind="$(fuzzpipe_target_source_kind "$TARGET")"

  cat > "$META_FILE" <<EOF
{
  "target": "$TARGET",
  "target_family": "$target_family",
  "target_source_kind": "$target_source_kind",
  "coverage_enabled": $(if [[ "${FUZZPIPE_ENABLE_COVERAGE:-0}" == "1" ]]; then echo true; else echo false; fi),
  "coverage_dir": "$COVERAGE_DIR",
  "seed_corpus_dir": "$SEED_DIR",
  "previous_corpus_dir": "${PREVIOUS_CORPUS_DIR:-}",
  "mode": "$MODE",
  "run_id": "$RUN_ID",
  "timestamp": "$(date -Iseconds)",
  "docker_image": "${DOCKER_IMAGE_TAG:-unknown}",
  "target_version": "$target_version",
  "target_ref": "$effective_target_ref",
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

find_previous_run_corpus_dir() {
  local runs_root="$ROOT/artifacts/runs/$TARGET"

  if [ ! -d "$runs_root" ]; then
    return 0
  fi

  local previous_run
  previous_run="$(find "$runs_root" -mindepth 1 -maxdepth 1 -type d ! -name "$RUN_ID" | sort | tail -n 1 || true)"

  if [ -z "$previous_run" ]; then
    return 0
  fi

  local previous_corpus="$previous_run/corpus"
  if [ -d "$previous_corpus" ]; then
    echo "$previous_corpus"
  fi
}

generate_coverage_artifacts() {
  if [[ "${FUZZPIPE_ENABLE_COVERAGE:-0}" != "1" ]]; then
    return 0
  fi

  if [[ "$MODE" == "demo-crash" ]]; then
    echo "[+] Coverage skipped for demo-crash mode" | tee -a "$LOG_FILE"
    return 0
  fi

  if ! command -v llvm-profdata >/dev/null 2>&1; then
    echo "[-] llvm-profdata not found, skipping coverage generation" | tee -a "$LOG_FILE"
    return 0
  fi

  if ! command -v llvm-cov >/dev/null 2>&1; then
    echo "[-] llvm-cov not found, skipping coverage generation" | tee -a "$LOG_FILE"
    return 0
  fi

  if [ ! -x "$FUZZER" ]; then
    echo "[-] Coverage skipped: fuzzer binary not found: $FUZZER" | tee -a "$LOG_FILE"
    return 0
  fi

  if [ ! -d "$CORPUS_DIR" ]; then
    echo "[-] Coverage skipped: corpus dir not found: $CORPUS_DIR" | tee -a "$LOG_FILE"
    return 0
  fi

  mapfile -t corpus_files < <(find "$CORPUS_DIR" -maxdepth 1 -type f | sort)

  if [ "${#corpus_files[@]}" -eq 0 ]; then
    echo "[+] Coverage skipped: no corpus inputs available" | tee -a "$LOG_FILE"
    return 0
  fi

  local profraw="$COVERAGE_DIR/coverage.profraw"
  local profdata="$COVERAGE_DIR/coverage.profdata"
  local summary_txt="$COVERAGE_DIR/coverage-summary.txt"
  local replay_log="$COVERAGE_DIR/coverage-replay.log"
  local html_dir="$COVERAGE_DIR/html"

  rm -f "$profraw" "$profdata" "$summary_txt"
  rm -rf "$html_dir"
  mkdir -p "$html_dir"

  echo "[+] Generating coverage artifacts" | tee -a "$LOG_FILE"
  echo "[+] Coverage dir: $COVERAGE_DIR" | tee -a "$LOG_FILE"

  export LLVM_PROFILE_FILE="$profraw"
  export FUZZPIPE_DEMO_CRASH=0

  set +e
  "$FUZZER" "${corpus_files[@]}" >"$replay_log" 2>&1
  local replay_exit=$?
  set -e

  echo "[+] Coverage replay exit code: $replay_exit" | tee -a "$LOG_FILE"

  if [ ! -f "$profraw" ]; then
    echo "[-] Coverage skipped: raw profile not generated" | tee -a "$LOG_FILE"
    return 0
  fi

  llvm-profdata merge -sparse "$profraw" -o "$profdata"
  llvm-cov report "$FUZZER" -instr-profile="$profdata" > "$summary_txt"
  llvm-cov show "$FUZZER" -instr-profile="$profdata" -format=html -output-dir="$html_dir" >/dev/null

  echo "[+] Coverage summary: $summary_txt" | tee -a "$LOG_FILE"
  echo "[+] Coverage HTML dir: $html_dir" | tee -a "$LOG_FILE"
}

echo "[+] Run dir: $RUN_DIR" | tee -a "$LOG_FILE"

FETCH_SCRIPT="$(fuzzpipe_target_fetch_script "$ROOT" "$TARGET")"
BUILD_SCRIPT="$(fuzzpipe_target_build_script "$ROOT" "$TARGET")"
TARGET_REPO="$(fuzzpipe_target_git_repo_dir "$ROOT" "$TARGET")"
FUZZER="$(fuzzpipe_target_fuzzer_path "$ROOT" "$TARGET")"
DICT_FILE="$(fuzzpipe_target_dict_file "$ROOT" "$TARGET" || true)"
SEED_DIR="$(fuzzpipe_target_initial_corpus_dir "$ROOT" "$TARGET")"
DEMO_SEED="$(fuzzpipe_target_demo_seed "$ROOT" "$TARGET")"

echo "[+] Fetching target sources ($TARGET)" | tee -a "$LOG_FILE"
bash "$FETCH_SCRIPT" 2>&1 | tee -a "$LOG_FILE"

TARGET_VERSION="unknown"
if [ -d "$TARGET_REPO/.git" ]; then
  TARGET_VERSION="$(git -C "$TARGET_REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

echo "[+] Building target fuzzer" | tee -a "$LOG_FILE"
bash "$BUILD_SCRIPT" 2>&1 | tee -a "$LOG_FILE"

write_meta "$TARGET_VERSION"

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

  if [ -f "$DEMO_SEED" ]; then
    cp "$DEMO_SEED" "$CORPUS_DIR/seed_CRASHME.txt"
    echo "[+] Added demo seed to corpus: seed_CRASHME.txt" | tee -a "$LOG_FILE"
  else
    echo "[-] Demo seed not found at $DEMO_SEED" | tee -a "$LOG_FILE"
  fi
fi

# Initial seed corpus
if [ -d "$SEED_DIR" ]; then
  echo "[+] Loading initial corpus from $SEED_DIR" | tee -a "$LOG_FILE"
  cp -n "$SEED_DIR"/* "$CORPUS_DIR"/ 2>/dev/null || true
fi

# Reuse corpus from previous run of the same target
PREVIOUS_CORPUS_DIR="$(find_previous_run_corpus_dir || true)"
if [ -n "${PREVIOUS_CORPUS_DIR:-}" ] && [ -d "$PREVIOUS_CORPUS_DIR" ]; then
  echo "[+] Reusing corpus from previous run: $PREVIOUS_CORPUS_DIR" | tee -a "$LOG_FILE"
  cp -n "$PREVIOUS_CORPUS_DIR"/* "$CORPUS_DIR"/ 2>/dev/null || true
fi

echo "[+] Running libFuzzer" | tee -a "$LOG_FILE"
fuzzpipe_print_diagnostics_env | tee -a "$LOG_FILE"
echo "[+] FUZZPIPE_DEMO_CRASH=$FUZZPIPE_DEMO_CRASH" | tee -a "$LOG_FILE"

FUZZ_ARGS=(
  "-artifact_prefix=$CRASH_DIR/"
  "-max_len=$MAX_LEN"
  "-timeout=$TIMEOUT"
)

if [ -n "${DICT_FILE:-}" ] && [ -f "$DICT_FILE" ]; then
  echo "[+] Using dictionary: $DICT_FILE" | tee -a "$LOG_FILE"
  FUZZ_ARGS+=("-dict=$DICT_FILE")
fi

if [ "$MAX_TOTAL_TIME" != "0" ]; then
  FUZZ_ARGS+=("-max_total_time=$MAX_TOTAL_TIME")
fi

set +e
"$FUZZER" "${FUZZ_ARGS[@]}" "$CORPUS_DIR" 2>&1 | tee -a "$LOG_FILE"
fuzzer_exit_code=${PIPESTATUS[0]}
set -e

echo "[+] Fuzzer exit code: $fuzzer_exit_code" | tee -a "$LOG_FILE"

generate_coverage_artifacts

exit "$fuzzer_exit_code"
