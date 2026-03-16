#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


STACK_LINE_RE = re.compile(r"^\s*#\d+\s+.*$")
ADDR_RE = re.compile(r"0x[0-9a-fA-F]+")
BUILDID_RE = re.compile(r"\(BuildId: [^)]+\)")
WS_RE = re.compile(r"\s+")

ASAN_ERROR_RE = re.compile(r"ERROR:\s+AddressSanitizer:\s+([A-Za-z0-9_-]+)")
UBSAN_ERROR_RE = re.compile(r"runtime error:\s+(.*)")
LIBFUZZER_ERROR_RE = re.compile(r"ERROR:\s+libFuzzer:\s+(.+)")

STACK_FRAME_LOCATION_RE = re.compile(
    r"^\s*#\d+\s+.*?\sin\s+(?P<func>.+?)\s+(?P<file>/[^:\s]+):(?P<line>\d+)(?::\d+)?\s*$"
)

ASAN_SUMMARY_RE = re.compile(
    r"SUMMARY:\s+AddressSanitizer:\s+(?P<crash_type>[A-Za-z0-9_-]+)\s+(?P<file>/[^:\s]+):(?P<line>\d+)\s+in\s+(?P<func>.+)"
)


@dataclass
class MinimizeInfo:
    crash_path: str
    minimized_path: str
    original_size: int
    minimized_size: int
    reduction_percent: float
    meta_path: str


@dataclass
class CrashResult:
    crash_file: str
    crash_path: str
    exit_code: int
    signature: str
    signature_hash: str
    stacktrace: list[str]
    log_path: str
    crash_type: str
    crash_function: str
    crash_file_path: str
    crash_line: int | None
    bucket_type: str
    bucket_function: str
    bucket_location: str
    crash_origin: str
    minimized_path: str | None
    original_size: int | None
    minimized_size: int | None
    reduction_percent: float | None
    minimize_meta_path: str | None


def run_cmd(cmd: list[str], timeout_sec: int = 30, extra_env: dict[str, str] | None = None) -> tuple[int, str]:
    env = os.environ.copy()

    llvm_symbolizer = subprocess.getoutput("command -v llvm-symbolizer").strip()
    if llvm_symbolizer:
        env.setdefault("ASAN_SYMBOLIZER_PATH", llvm_symbolizer)

    env.setdefault("UBSAN_OPTIONS", "print_stacktrace=1:halt_on_error=1")
    env.setdefault("ASAN_OPTIONS", "symbolize=1:detect_leaks=0:abort_on_error=1")

    if extra_env:
        env.update(extra_env)

    proc = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout_sec,
        check=False,
        env=env,
    )
    return proc.returncode, proc.stdout


def normalize_stack_line(line: str) -> str:
    line = ADDR_RE.sub("0xADDR", line)
    line = BUILDID_RE.sub("", line)
    line = WS_RE.sub(" ", line).strip()
    return line


def extract_stacktrace(output: str) -> list[str]:
    lines = output.splitlines()
    stack: list[str] = []

    in_stack = False
    for ln in lines:
        if (
            "ERROR: libFuzzer:" in ln
            or "ERROR: AddressSanitizer:" in ln
            or "AddressSanitizer:" in ln
            or "UndefinedBehaviorSanitizer" in ln
            or "runtime error:" in ln
        ):
            in_stack = True

        if in_stack and STACK_LINE_RE.match(ln):
            stack.append(normalize_stack_line(ln))

        if in_stack and ln.startswith("SUMMARY:"):
            break

    if not stack:
        for ln in lines:
            if STACK_LINE_RE.match(ln):
                stack.append(normalize_stack_line(ln))
            if len(stack) >= 30:
                break

    return stack


def signature_from_stack(stack: list[str]) -> str:
    top = stack[:12] if stack else ["NO_STACKTRACE"]
    return "\n".join(top)


def sha256_hex(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def load_meta(run_dir: Path) -> dict[str, Any]:
    meta_file = run_dir / "meta.json"
    if meta_file.exists():
        return json.loads(meta_file.read_text(encoding="utf-8"))
    return {}


def load_minimized_index(target: str) -> dict[str, MinimizeInfo]:
    minimized_root = Path("/workspace/artifacts/minimized") / target
    index: dict[str, MinimizeInfo] = {}

    if not minimized_root.exists():
        return index

    for meta_file in minimized_root.glob("*/minimize_meta.json"):
        try:
            data = json.loads(meta_file.read_text(encoding="utf-8"))
        except Exception:
            continue

        crash_path = str(data.get("crash_path", "")).strip()
        minimized_path = str(data.get("minimized_path", "")).strip()

        if not crash_path:
            continue

        index[crash_path] = MinimizeInfo(
            crash_path=crash_path,
            minimized_path=minimized_path,
            original_size=int(data.get("original_size", 0)),
            minimized_size=int(data.get("minimized_size", 0)),
            reduction_percent=float(data.get("reduction_percent", 0)),
            meta_path=str(meta_file),
        )

    return index


def detect_crash_type(output: str) -> str:
    for line in output.splitlines():
        m = ASAN_ERROR_RE.search(line)
        if m:
            return m.group(1).strip()

    for line in output.splitlines():
        m = UBSAN_ERROR_RE.search(line)
        if m:
            return f"ubsan: {m.group(1).strip()}"

    for line in output.splitlines():
        m = LIBFUZZER_ERROR_RE.search(line)
        if m:
            return m.group(1).strip()

    return "unknown"


def extract_root_cause(output: str, stack: list[str]) -> tuple[str, str, int | None]:
    lines = output.splitlines()

    for raw in lines:
        m = ASAN_SUMMARY_RE.search(raw.strip())
        if m:
            func = m.group("func").strip()
            file_path = m.group("file").strip()
            line = int(m.group("line"))
            return func, file_path, line

    for frame in stack:
        m = STACK_FRAME_LOCATION_RE.match(frame)
        if not m:
            continue

        func = m.group("func").strip()
        file_path = m.group("file").strip()
        line = int(m.group("line"))

        if "libFuzzer" in func or "fuzzer::" in func:
            continue
        if "__sanitizer" in func:
            continue
        if "/usr/" in file_path or "/lib/" in file_path:
            continue

        return func, file_path, line

    for frame in stack:
        m = STACK_FRAME_LOCATION_RE.match(frame)
        if m:
            func = m.group("func").strip()
            file_path = m.group("file").strip()
            line = int(m.group("line"))
            return func, file_path, line

    return "unknown", "unknown", None


def make_location_bucket(file_path: str, line: int | None) -> str:
    if file_path == "unknown" or line is None:
        return "unknown"
    return f"{file_path}:{line}"


def build_repro_env(meta: dict[str, Any]) -> dict[str, str]:
    env: dict[str, str] = {}

    mode = str(meta.get("mode", "")).strip().lower()
    if mode == "demo-crash":
        env["FUZZPIPE_DEMO_CRASH"] = "1"

    return env


def detect_crash_origin(meta: dict[str, Any]) -> str:
    mode = str(meta.get("mode", "")).strip().lower()
    if mode == "demo-crash":
        return "demo"
    return "real"


def triage_run(target: str, run_dir: Path, fuzzer_path: Path, timeout_sec: int) -> dict[str, Any]:
    crashes_dir = run_dir / "crashes"
    if not crashes_dir.exists():
        raise SystemExit(f"Crashes directory not found: {crashes_dir}")

    crash_files = sorted([p for p in crashes_dir.iterdir() if p.is_file()])
    meta = load_meta(run_dir)
    repro_env = build_repro_env(meta)
    minimized_index = load_minimized_index(target)
    crash_origin = detect_crash_origin(meta)

    report_dir = Path("/workspace/artifacts/reports") / target / run_dir.name
    ensure_dir(report_dir)

    results: list[CrashResult] = []
    signatures: dict[str, list[str]] = {}
    by_type: dict[str, list[str]] = {}
    by_function: dict[str, list[str]] = {}
    by_location: dict[str, list[str]] = {}

    for crash in crash_files:
        log_path = report_dir / f"{crash.name}.repro.log"

        cmd = [str(fuzzer_path), str(crash)]
        exit_code, out = run_cmd(cmd, timeout_sec=timeout_sec, extra_env=repro_env)

        log_path.write_text(out, encoding="utf-8")

        stack = extract_stacktrace(out)
        sig = signature_from_stack(stack)
        sig_hash = sha256_hex(sig)

        crash_type = detect_crash_type(out)
        crash_function, crash_file_path, crash_line = extract_root_cause(out, stack)

        bucket_type = crash_type or "unknown"
        bucket_function = crash_function or "unknown"
        bucket_location = make_location_bucket(crash_file_path, crash_line)

        min_info = minimized_index.get(str(crash))

        result = CrashResult(
            crash_file=crash.name,
            crash_path=str(crash),
            exit_code=exit_code,
            signature=sig,
            signature_hash=sig_hash,
            stacktrace=stack,
            log_path=str(log_path),
            crash_type=crash_type,
            crash_function=crash_function,
            crash_file_path=crash_file_path,
            crash_line=crash_line,
            bucket_type=bucket_type,
            bucket_function=bucket_function,
            bucket_location=bucket_location,
            crash_origin=crash_origin,
            minimized_path=min_info.minimized_path if min_info else None,
            original_size=min_info.original_size if min_info else None,
            minimized_size=min_info.minimized_size if min_info else None,
            reduction_percent=min_info.reduction_percent if min_info else None,
            minimize_meta_path=min_info.meta_path if min_info else None,
        )
        results.append(result)

        signatures.setdefault(sig_hash, []).append(crash.name)
        by_type.setdefault(bucket_type, []).append(crash.name)
        by_function.setdefault(bucket_function, []).append(crash.name)
        by_location.setdefault(bucket_location, []).append(crash.name)

    unique = len(signatures)
    total = len(results)
    target_ref = str(meta.get("target_ref", "unknown"))

    report_json = {
        "target": target,
        "run_dir": str(run_dir),
        "run_id": run_dir.name,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "meta": meta,
        "target_ref": target_ref,
        "crash_origin": crash_origin,
        "repro_env": repro_env,
        "counts": {
            "total_crashes": total,
            "unique_signatures": unique,
            "unique_crash_types": len(by_type),
            "unique_functions": len(by_function),
            "unique_locations": len(by_location),
        },
        "signatures": [
            {
                "signature_hash": h,
                "crashes": names,
            }
            for h, names in sorted(signatures.items(), key=lambda x: (-len(x[1]), x[0]))
        ],
        "buckets": {
            "by_crash_type": [
                {"crash_type": k, "crashes": v}
                for k, v in sorted(by_type.items(), key=lambda x: (-len(x[1]), x[0]))
            ],
            "by_function": [
                {"function": k, "crashes": v}
                for k, v in sorted(by_function.items(), key=lambda x: (-len(x[1]), x[0]))
            ],
            "by_location": [
                {"location": k, "crashes": v}
                for k, v in sorted(by_location.items(), key=lambda x: (-len(x[1]), x[0]))
            ],
        },
        "crashes": [
            {
                "crash_file": r.crash_file,
                "crash_path": r.crash_path,
                "exit_code": r.exit_code,
                "signature_hash": r.signature_hash,
                "crash_type": r.crash_type,
                "crash_function": r.crash_function,
                "crash_file_path": r.crash_file_path,
                "crash_line": r.crash_line,
                "bucket_type": r.bucket_type,
                "bucket_function": r.bucket_function,
                "bucket_location": r.bucket_location,
                "crash_origin": r.crash_origin,
                "stacktrace": r.stacktrace,
                "log_path": r.log_path,
                "minimized_path": r.minimized_path,
                "original_size": r.original_size,
                "minimized_size": r.minimized_size,
                "reduction_percent": r.reduction_percent,
                "minimize_meta_path": r.minimize_meta_path,
            }
            for r in results
        ],
    }

    (report_dir / "report.json").write_text(json.dumps(report_json, indent=2), encoding="utf-8")

    lines: list[str] = []
    lines.append(f"# Fuzz Triage Report — {target}")
    lines.append("")
    lines.append(f"- **Run ID:** `{run_dir.name}`")
    lines.append(f"- **Run dir:** `{run_dir}`")
    lines.append(f"- **Generated:** `{report_json['generated_at']}`")
    lines.append(f"- **Target ref:** `{target_ref}`")
    lines.append(f"- **Crash origin:** `{crash_origin}`")
    lines.append(f"- **Total crashes:** **{total}**")
    lines.append(f"- **Unique signatures:** **{unique}**")
    lines.append(f"- **Unique crash types:** **{len(by_type)}**")
    lines.append(f"- **Unique functions:** **{len(by_function)}**")
    lines.append(f"- **Unique locations:** **{len(by_location)}**")
    lines.append("")

    if meta:
        lines.append("## Meta")
        lines.append("```json")
        lines.append(json.dumps(meta, indent=2))
        lines.append("```")
        lines.append("")

    if repro_env:
        lines.append("## Repro environment")
        lines.append("```json")
        lines.append(json.dumps(repro_env, indent=2))
        lines.append("```")
        lines.append("")

    lines.append("## Signatures (dedup)")
    lines.append("")
    for entry in report_json["signatures"]:
        h = entry["signature_hash"]
        names = entry["crashes"]
        lines.append(f"### `{h[:12]}` — {len(names)} crash(es)")
        lines.append("")
        for n in names:
            lines.append(f"- `{n}`")
        lines.append("")

    lines.append("## Buckets by crash type")
    lines.append("")
    for entry in report_json["buckets"]["by_crash_type"]:
        lines.append(f"### `{entry['crash_type']}` — {len(entry['crashes'])} crash(es)")
        lines.append("")
        for n in entry["crashes"]:
            lines.append(f"- `{n}`")
        lines.append("")

    lines.append("## Buckets by function")
    lines.append("")
    for entry in report_json["buckets"]["by_function"]:
        lines.append(f"### `{entry['function']}` — {len(entry['crashes'])} crash(es)")
        lines.append("")
        for n in entry["crashes"]:
            lines.append(f"- `{n}`")
        lines.append("")

    lines.append("## Buckets by location")
    lines.append("")
    for entry in report_json["buckets"]["by_location"]:
        lines.append(f"### `{entry['location']}` — {len(entry['crashes'])} crash(es)")
        lines.append("")
        for n in entry["crashes"]:
            lines.append(f"- `{n}`")
        lines.append("")

    lines.append("## Crash details")
    lines.append("")
    for r in results:
        lines.append(f"### `{r.crash_file}`")
        lines.append("")
        lines.append(f"- **Exit code:** `{r.exit_code}`")
        lines.append(f"- **Crash origin:** `{r.crash_origin}`")
        lines.append(f"- **Signature:** `{r.signature_hash}`")
        lines.append(f"- **Crash type:** `{r.crash_type}`")
        lines.append(f"- **Function:** `{r.crash_function}`")
        lines.append(f"- **File:** `{r.crash_file_path}`")
        lines.append(f"- **Line:** `{r.crash_line}`")
        if r.minimized_path:
            lines.append(f"- **Minimized path:** `{r.minimized_path}`")
            lines.append(f"- **Original size:** `{r.original_size}`")
            lines.append(f"- **Minimized size:** `{r.minimized_size}`")
            lines.append(f"- **Reduction %:** `{r.reduction_percent}`")
            lines.append(f"- **Minimize meta:** `{r.minimize_meta_path}`")
        lines.append(f"- **Repro log:** `{Path(r.log_path).as_posix()}`")
        lines.append("")
        if r.stacktrace:
            lines.append("```")
            lines.extend(r.stacktrace[:30])
            lines.append("```")
        else:
            lines.append("_No stacktrace extracted._")
        lines.append("")

    (report_dir / "report.md").write_text("\n".join(lines), encoding="utf-8")

    return {
        "report_dir": str(report_dir),
        "report_md": str(report_dir / "report.md"),
        "report_json": str(report_dir / "report.json"),
        "target_ref": target_ref,
        "crash_origin": crash_origin,
        "total_crashes": total,
        "unique_signatures": unique,
        "unique_crash_types": len(by_type),
        "unique_functions": len(by_function),
        "unique_locations": len(by_location),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Triage crashes for a fuzz run and generate report.")
    ap.add_argument("--target", default="cjson", help="Target name (default: cjson)")
    ap.add_argument("--run", required=True, help="Run directory (repo-relative or absolute)")
    ap.add_argument("--timeout", type=int, default=20, help="Timeout seconds per crash repro")
    args = ap.parse_args()

    target = args.target

    run_arg = args.run
    run_dir = Path(run_arg)
    if not run_dir.is_absolute():
        run_dir = Path("/workspace") / run_arg

    if target == "cjson":
        fuzzer_path = Path("/workspace/targets/cjson/out/cjson_fuzzer")
    else:
        raise SystemExit(f"Unknown target: {target}")

    if not fuzzer_path.exists():
        raise SystemExit(f"Fuzzer binary not found: {fuzzer_path} (did you build?)")

    summary = triage_run(target, run_dir, fuzzer_path, timeout_sec=args.timeout)
    print("[+] Triage complete")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()