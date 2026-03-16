#!/usr/bin/env bash
set -euo pipefail

fuzzpipe_build_cjson_target() {
  local root="$1"
  local target="$2"
  local repo_subdir="$3"

  local src="$root/targets/$target/src/$repo_subdir"
  local out="$root/targets/$target/out"

  source "$root/scripts/diagnostics_env.sh"
  fuzzpipe_setup_diagnostics_env

  mkdir -p "$out"

  local cjson_obj="$out/cJSON.o"
  local harness_obj="$out/harness.o"
  local fuzzer_bin="$out/${target}_fuzzer"

  local common_flags=(
    -O1
    -g
    -fno-omit-frame-pointer
    -fno-optimize-sibling-calls
  )

  local san_flags=(
    "-fsanitize=${FUZZPIPE_SANITIZERS}"
  )

  local fuzz_cov_flags=(
    -fsanitize=fuzzer-no-link
  )

  local yaml_defines=(
    -DHAVE_CONFIG_H
  )

  echo "[+] Build root: $root"
  echo "[+] Source dir: $src"
  echo "[+] Output dir: $out"
  echo "[+] Sanitizers: $FUZZPIPE_SANITIZERS"

  echo "[+] Compiling cJSON.c as C"
  clang \
    -I"$src" \
    "${common_flags[@]}" \
    "${san_flags[@]}" \
    "${fuzz_cov_flags[@]}" \
    -c "$src/cJSON.c" \
    -o "$cjson_obj"

  echo "[+] Compiling harness.cpp as C++"
  clang++ \
    -I"$src" \
    "${common_flags[@]}" \
    "${san_flags[@]}" \
    "${fuzz_cov_flags[@]}" \
    -c "$root/targets/$target/harness.cpp" \
    -o "$harness_obj"

  echo "[+] Linking fuzzer"
  clang++ \
    "${common_flags[@]}" \
    "${san_flags[@]}" \
    -fsanitize=fuzzer \
    "$harness_obj" \
    "$cjson_obj" \
    -o "$fuzzer_bin"

  echo "[+] Built: $fuzzer_bin"
}
#!/usr/bin/env bash
set -euo pipefail

fuzzpipe_build_cjson_target() {
  local root="$1"
  local target="$2"
  local repo_subdir="$3"

  local src="$root/targets/$target/src/$repo_subdir"
  local out="$root/targets/$target/out"

  source "$root/scripts/diagnostics_env.sh"
  fuzzpipe_setup_diagnostics_env

  mkdir -p "$out"

  local cjson_obj="$out/cJSON.o"
  local harness_obj="$out/harness.o"
  local fuzzer_bin="$out/${target}_fuzzer"

  local common_flags=(
    -O1
    -g
    -fno-omit-frame-pointer
    -fno-optimize-sibling-calls
  )

  local san_flags=(
    "-fsanitize=${FUZZPIPE_SANITIZERS}"
  )

  local fuzz_cov_flags=(
    -fsanitize=fuzzer-no-link
  )

  echo "[+] Build root: $root"
  echo "[+] Source dir: $src"
  echo "[+] Output dir: $out"
  echo "[+] Sanitizers: $FUZZPIPE_SANITIZERS"

  echo "[+] Compiling cJSON.c as C"
  clang \
    -I"$src" \
    "${common_flags[@]}" \
    "${san_flags[@]}" \
    "${fuzz_cov_flags[@]}" \
    -c "$src/cJSON.c" \
    -o "$cjson_obj"

  echo "[+] Compiling harness.cpp as C++"
  clang++ \
    -I"$src" \
    "${common_flags[@]}" \
    "${san_flags[@]}" \
    "${fuzz_cov_flags[@]}" \
    -c "$root/targets/$target/harness.cpp" \
    -o "$harness_obj"

  echo "[+] Linking fuzzer"
  clang++ \
    "${common_flags[@]}" \
    "${san_flags[@]}" \
    -fsanitize=fuzzer \
    "$harness_obj" \
    "$cjson_obj" \
    -o "$fuzzer_bin"

  echo "[+] Built: $fuzzer_bin"
}


fuzzpipe_build_libyaml_target() {
  local root="$1"
  local target="$2"
  local repo_subdir="$3"

  local repo_root="$root/targets/$target/src/$repo_subdir"
  local src="$repo_root/src"
  local include="$repo_root/include"
  local out="$root/targets/$target/out"
  local generated="$out/generated"

  source "$root/scripts/diagnostics_env.sh"
  fuzzpipe_setup_diagnostics_env

  mkdir -p "$out" "$generated"

  local api_obj="$out/api.o"
  local reader_obj="$out/reader.o"
  local scanner_obj="$out/scanner.o"
  local parser_obj="$out/parser.o"
  local loader_obj="$out/loader.o"
  local writer_obj="$out/writer.o"
  local emitter_obj="$out/emitter.o"
  local dumper_obj="$out/dumper.o"
  local harness_obj="$out/harness.o"
  local fuzzer_bin="$out/${target}_fuzzer"

  local yaml_major="0"
  local yaml_minor="2"
  local yaml_patch="5"

  local yaml_version_string="${yaml_major}.${yaml_minor}.${yaml_patch}"

  cat > "$generated/config.h" <<EOF
#define YAML_VERSION_MAJOR $yaml_major
#define YAML_VERSION_MINOR $yaml_minor
#define YAML_VERSION_PATCH $yaml_patch
#define YAML_VERSION_STRING "$yaml_version_string"
EOF

  local common_flags=(
    -O1
    -g
    -fno-omit-frame-pointer
    -fno-optimize-sibling-calls
  )

  local san_flags=(
    "-fsanitize=${FUZZPIPE_SANITIZERS}"
  )

  local fuzz_cov_flags=(
    -fsanitize=fuzzer-no-link
  )

  local yaml_defines=(
    -DHAVE_CONFIG_H
  )

  echo "[+] Build root: $root"
  echo "[+] Repo root: $repo_root"
  echo "[+] Source dir: $src"
  echo "[+] Include dir: $include"
  echo "[+] Generated dir: $generated"
  echo "[+] Output dir: $out"
  echo "[+] Sanitizers: $FUZZPIPE_SANITIZERS"

  for file in api reader scanner parser loader writer emitter dumper; do
    echo "[+] Compiling $file.c"
    clang \
      -I"$generated" \
      -I"$include" \
      -I"$src" \
      "${yaml_defines[@]}" \
      "${common_flags[@]}" \
      "${san_flags[@]}" \
      "${fuzz_cov_flags[@]}" \
      -c "$src/$file.c" \
      -o "$out/$file.o"
  done

  echo "[+] Compiling harness.cpp"
  clang++ \
    -I"$generated" \
    -I"$include" \
    -I"$src" \
    "${yaml_defines[@]}" \
    "${common_flags[@]}" \
    "${san_flags[@]}" \
    "${fuzz_cov_flags[@]}" \
    -c "$root/targets/$target/harness.cpp" \
    -o "$harness_obj"

  echo "[+] Linking fuzzer"
  clang++ \
    "${common_flags[@]}" \
    "${san_flags[@]}" \
    -fsanitize=fuzzer \
    "$harness_obj" \
    "$api_obj" \
    "$reader_obj" \
    "$scanner_obj" \
    "$parser_obj" \
    "$loader_obj" \
    "$writer_obj" \
    "$emitter_obj" \
    "$dumper_obj" \
    -o "$fuzzer_bin"

  echo "[+] Built: $fuzzer_bin"
}
