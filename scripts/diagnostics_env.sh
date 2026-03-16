#!/usr/bin/env bash
set -euo pipefail

# Shared diagnostic configuration for fuzz / repro / minimize / triage.
# Source this file from other scripts:
#   source "$ROOT/scripts/diagnostics_env.sh"
#   fuzzpipe_setup_diagnostics_env

fuzzpipe_setup_diagnostics_env() {
  export FUZZPIPE_SANITIZERS="${FUZZPIPE_SANITIZERS:-address,undefined}"

  local detected_symbolizer=""
  detected_symbolizer="$(command -v llvm-symbolizer 2>/dev/null || true)"

  export ASAN_SYMBOLIZER_PATH="${ASAN_SYMBOLIZER_PATH:-$detected_symbolizer}"
  export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=1}"
  export ASAN_OPTIONS="${ASAN_OPTIONS:-symbolize=1:detect_leaks=0:abort_on_error=1}"

  # Extra metadata-friendly vars
  export FUZZPIPE_SYMBOLIZER_PATH="${ASAN_SYMBOLIZER_PATH:-}"
}

fuzzpipe_print_diagnostics_env() {
  echo "[+] FUZZPIPE_SANITIZERS=$FUZZPIPE_SANITIZERS"
  echo "[+] ASAN_SYMBOLIZER_PATH=${ASAN_SYMBOLIZER_PATH:-unset}"
  echo "[+] UBSAN_OPTIONS=$UBSAN_OPTIONS"
  echo "[+] ASAN_OPTIONS=$ASAN_OPTIONS"
  echo "[+] FUZZPIPE_SYMBOLIZER_PATH=${FUZZPIPE_SYMBOLIZER_PATH:-unset}"
}
