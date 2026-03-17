#!/usr/bin/env bash
set -euo pipefail

fuzzpipe_list_supported_targets() {
  echo "cjson cjson_old yaml sqlite"
}

fuzzpipe_assert_target_supported() {
  local target="$1"

  local supported
  supported=" $(fuzzpipe_list_supported_targets) "

  if [[ "$supported" != *" $target "* ]]; then
    echo "Unsupported target: $target"
    echo "Supported targets: $(fuzzpipe_list_supported_targets)"
    exit 1
  fi
}

fuzzpipe_target_family() {
  local target="$1"

  case "$target" in
    cjson|cjson_old)
      echo "cjson"
      ;;
    yaml)
      echo "libyaml"
      ;;
    sqlite)
      echo "sqlite"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

fuzzpipe_target_repo_subdir() {
  local target="$1"

  case "$target" in
    cjson|cjson_old)
      echo "cjson"
      ;;
    yaml)
      echo "libyaml"
      ;;
    sqlite)
      echo "sqlite"
      ;;
    *)
      echo ""
      ;;
  esac
}

fuzzpipe_target_source_kind() {
  local target="$1"

  case "$target" in
    cjson|cjson_old|yaml)
      echo "git"
      ;;
    sqlite)
      echo "archive"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

fuzzpipe_target_default_ref() {
  local target="$1"

  case "$target" in
    cjson)
      echo "master"
      ;;
    cjson_old)
      echo "v1.5.0"
      ;;
    yaml)
      echo "master"
      ;;
    sqlite)
      echo "3.51.0"
      ;;
    *)
      echo "master"
      ;;
  esac
}

fuzzpipe_target_dir() {
  local root="$1"
  local target="$2"

  fuzzpipe_assert_target_supported "$target"
  echo "$root/targets/$target"
}

fuzzpipe_target_fetch_script() {
  local root="$1"
  local target="$2"
  echo "$(fuzzpipe_target_dir "$root" "$target")/fetch.sh"
}

fuzzpipe_target_build_script() {
  local root="$1"
  local target="$2"
  echo "$(fuzzpipe_target_dir "$root" "$target")/build.sh"
}

fuzzpipe_target_out_dir() {
  local root="$1"
  local target="$2"
  echo "$(fuzzpipe_target_dir "$root" "$target")/out"
}

fuzzpipe_target_fuzzer_path() {
  local root="$1"
  local target="$2"
  echo "$(fuzzpipe_target_out_dir "$root" "$target")/${target}_fuzzer"
}

fuzzpipe_target_demo_seed() {
  local root="$1"
  local target="$2"
  echo "$root/artifacts/demo/$target/demo_seed.txt"
}

fuzzpipe_target_initial_corpus_dir() {
  local root="$1"
  local target="$2"
  echo "$root/corpus/initial/$target"
}

fuzzpipe_target_dict_file() {
  local root="$1"
  local target="$2"
  local dict_dir

  dict_dir="$(fuzzpipe_target_dir "$root" "$target")/dict"

  if [ ! -d "$dict_dir" ]; then
    return 0
  fi

  find "$dict_dir" -maxdepth 1 -type f -name "*.dict" | sort | head -n 1
}

fuzzpipe_target_src_root() {
  local root="$1"
  local target="$2"
  echo "$(fuzzpipe_target_dir "$root" "$target")/src"
}

fuzzpipe_target_git_repo_dir() {
  local root="$1"
  local target="$2"
  local src_root
  local git_dir

  src_root="$(fuzzpipe_target_src_root "$root" "$target")"

  if [ ! -d "$src_root" ]; then
    echo "$src_root"
    return 0
  fi

  git_dir="$(find "$src_root" -mindepth 1 -maxdepth 4 -type d -name ".git" 2>/dev/null | sort | head -n 1 || true)"

  if [ -n "$git_dir" ]; then
    dirname "$git_dir"
    return 0
  fi

  echo "$src_root"
}

fuzzpipe_assert_target_exists() {
  local root="$1"
  local target="$2"

  local target_dir
  local fetch_script
  local build_script

  fuzzpipe_assert_target_supported "$target"

  target_dir="$(fuzzpipe_target_dir "$root" "$target")"
  fetch_script="$(fuzzpipe_target_fetch_script "$root" "$target")"
  build_script="$(fuzzpipe_target_build_script "$root" "$target")"

  if [ ! -d "$target_dir" ]; then
    echo "Unknown target: $target"
    echo "Missing target directory: $target_dir"
    exit 1
  fi

  if [ ! -f "$fetch_script" ]; then
    echo "Missing fetch script for target '$target': $fetch_script"
    exit 1
  fi

  if [ ! -f "$build_script" ]; then
    echo "Missing build script for target '$target': $build_script"
    exit 1
  fi
}
