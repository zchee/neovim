#!/usr/bin/env bash
#
# Run the whole perf suite sequentially and write one JSONL file plus a
# human-readable table.
#
#   perf/run_all.sh [nvim-binary] [--quick]
#
# HAZARD: never invoke bare `make` from here or anywhere near a benchmark run.
# This repo's default target is `all: distclean rebase nvim/build clean/runtime
# install`, which fetches, rebases onto origin/master and installs to
# /usr/local -- it would destroy the very checkout being measured. Build with
# `make nvim`, `make nvim/build` or `cmake --build build --target nvim`.
#
# Benchmarks are run one at a time, never concurrently with each other or with
# a build; the machine is assumed otherwise idle.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVIM="${1:-$ROOT/build/bin/nvim}"
[ "${NVIM#--}" = "$NVIM" ] || NVIM="$ROOT/build/bin/nvim"
DRIVER="${PERF_DRIVER:-$NVIM}"
LABEL="${PERF_LABEL:-baseline}"
OUT="$ROOT/perf/out"
JSONL="$OUT/$LABEL.jsonl"
FACTS="$OUT/$LABEL.facts.json"

QUICK=0
for arg in "$@"; do
  [ "$arg" = "--quick" ] && QUICK=1
done

if [ "$QUICK" = 1 ]; then
  RUNS_HEAVY="${PERF_RUNS_HEAVY:-2}"
  RUNS_MICRO="${PERF_RUNS_MICRO:-3}"
  SCROLL_ITERS=100; PAGE_ITERS=25; KEYS=100; MICRO_ITERS=200000; RPC_LINES=20000
else
  RUNS_HEAVY="${PERF_RUNS_HEAVY:-5}"
  RUNS_MICRO="${PERF_RUNS_MICRO:-9}"
  SCROLL_ITERS=400; PAGE_ITERS=100; KEYS=400; MICRO_ITERS=1000000; RPC_LINES=100000
fi

mkdir -p "$OUT"
: > "$JSONL"

sha_before="$(git rev-parse HEAD)"
dirty_before="$(git status --porcelain -- src CMakeLists.txt cmake cmake.deps local.mk | wc -l | tr -d ' ')"

echo "== perf suite =="
echo "  nvim:     $NVIM ($("$NVIM" --version | head -1))"
echo "  driver:   $DRIVER"
echo "  sha:      $sha_before (build-relevant dirty files: $dirty_before)"
echo "  label:    $LABEL -> $JSONL"
echo

# --- static facts about the binary under test ---------------------------------
size_bytes="$(wc -c < "$NVIM" | tr -d ' ')"
exported_syms="$(nm -gU "$NVIM" 2>/dev/null | wc -l | tr -d ' ')"
localmk_md5="$( (md5 -q local.mk 2>/dev/null || md5sum local.mk | cut -d' ' -f1) 2>/dev/null || echo none)"
build_type="$(grep -m1 '^CMAKE_BUILD_TYPE:' build/CMakeCache.txt 2>/dev/null | cut -d= -f2 || echo unknown)"
lto="$(grep -m1 '^ENABLE_LTO:' build/CMakeCache.txt 2>/dev/null | cut -d= -f2 || echo unknown)"

# Max RSS on a representative treesitter workload (headless, no pty needed).
rss_mb="$(/usr/bin/time -l env PERF_FILE="$ROOT/perf/corpus/big.c" PERF_MODE=page \
  PERF_ITERS=100 PERF_TS=1 "$NVIM" --headless -u NONE -i NONE -n \
  -c "luafile $ROOT/perf/tui_workload.lua" 2>&1 >/dev/null |
  awk '/maximum resident set size/ {printf "%.1f", $1/1048576}' || echo 0)"

cat > "$FACTS" <<JSON
{
  "label": "$LABEL",
  "sha": "$sha_before",
  "date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "nvim": "$NVIM",
  "nvim_version": "$("$NVIM" --version | head -1)",
  "build_type": "$build_type",
  "enable_lto": "$lto",
  "local_mk_md5": "$localmk_md5",
  "binary_size_bytes": $size_bytes,
  "exported_symbols": $exported_syms,
  "max_rss_mb": $rss_mb,
  "uname": "$(uname -mrs)",
  "cpu": "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)",
  "runs_heavy": $RUNS_HEAVY,
  "runs_micro": $RUNS_MICRO
}
JSON

echo "  binary:   $size_bytes bytes, $exported_syms exported syms, max RSS ${rss_mb} MB"
echo "  build:    $build_type, LTO=$lto, local.mk md5=$localmk_md5"
echo

run() {
  local script="$1"; shift
  echo "-- $script"
  "$DRIVER" -u NONE -i NONE -n -l "$ROOT/perf/$script" "$NVIM" "$@" >> "$JSONL"
}

run bench_redraw.lua "--runs=$RUNS_HEAVY" "--scroll-iters=$SCROLL_ITERS" "--page-iters=$PAGE_ITERS"
run bench_tui.lua    "--runs=$RUNS_HEAVY" "--scroll-iters=$SCROLL_ITERS" "--page-iters=$PAGE_ITERS"
run bench_input.lua  "--runs=$RUNS_HEAVY" "--keys=$KEYS"
run bench_rpc.lua    "--runs=$RUNS_HEAVY" "--lines=$RPC_LINES"
run bench_micro.lua  "--runs=$RUNS_MICRO" "--iters=$MICRO_ITERS"

sha_after="$(git rev-parse HEAD)"
if [ "$sha_before" != "$sha_after" ]; then
  echo "ABORT: HEAD moved during the run ($sha_before -> $sha_after); results are void." >&2
  exit 1
fi

echo
printf '%-8s %-22s %14s %14s %8s %s\n' BENCH CASE MEDIAN MIN/MAX RSD% EXTRA
jq -r '
  def fmt(v): if v == null then "-"
    elif v >= 1e9 then ((v/1e9*1000|round)/1000|tostring) + "s"
    elif v >= 1e6 then ((v/1e6*1000|round)/1000|tostring) + "ms"
    elif v >= 1e3 then ((v/1e3*10|round)/10|tostring) + "us"
    else ((v*10|round)/10|tostring) + "ns" end;
  [ .bench, .case, fmt(.stats.median), fmt(.stats.min) + "/" + fmt(.stats.max),
    ((.stats.rsd_pct*10|round)/10|tostring),
    ( if .writes_per_frame != null then "writes/frame=" + ((.writes_per_frame*100|round)/100|tostring)
      elif .bytes_per_frame != null then "bytes/frame=" + ((.bytes_per_frame|round)|tostring)
      elif .mb_per_s != null then "MB/s=" + ((.mb_per_s*10|round)/10|tostring)
      elif .p95_ns != null then "p95=" + fmt(.p95_ns)
      else "" end)
  ] | @tsv' "$JSONL" |
  while IFS=$'\t' read -r b c m mm r e; do
    printf '%-8s %-22s %14s %14s %8s %s\n' "$b" "$c" "$m" "$mm" "$r" "$e"
  done

echo
echo "JSONL: $JSONL"
echo "Facts: $FACTS"
echo "SHA unchanged across the run: $sha_after"
