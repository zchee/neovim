# perf/ -- Neovim benchmark harness

A self-contained benchmark suite for this fork's optimization work. It needs no
Python, no pynvim and no new dependencies: every script runs under the nvim
binary itself (`nvim -l`), speaking msgpack-RPC to a child nvim through
`vim.uv` + `vim.mpack`, reusing the stream/RPC framing in `test/client/`.

## HAZARD: never run bare `make`

This repository's default `make` target is

    all: distclean rebase nvim/build clean/runtime install

which runs `git fetch`, **rebases the branch onto `origin/master`**, and
installs into `/usr/local`. Running it during (or near) a benchmark session
destroys the checkout being measured. Build only with:

    make nvim              # or
    make nvim/build        # adds codesigning
    cmake --build build --target nvim

`local.mk` drives the local configuration (Release, `ENABLE_LTO=ON`,
`-O3 -mcpu=apple-m3 -ffast-math`); its md5 is recorded with every result set so
numbers from different flag sets are never compared by accident.

## Running

    perf/run_all.sh                       # full suite on ./build/bin/nvim
    perf/run_all.sh /path/to/nvim         # a specific binary
    perf/run_all.sh --quick               # reduced iterations, for smoke tests
    PERF_LABEL=w2.1 perf/run_all.sh       # writes perf/out/w2.1.jsonl

Each script also runs standalone, taking the nvim binary as its first argument:

    nvim -u NONE -i NONE -n -l perf/bench_redraw.lua ./build/bin/nvim --runs=9

`run_all.sh` records the git SHA before and after the suite and aborts if HEAD
moved. It also captures binary size, exported-symbol count (`nm -gU`), max RSS
and the `local.mk` hash into `perf/out/<label>.facts.json`.

## What is measured

| Script | Cases | Metric |
| --- | --- | --- |
| `bench_redraw.lua` | `{ascii,cjk,ts}_{scroll,page}` | ns/frame over the remote-UI path, plus UI events/frame and bytes/frame |
| `bench_tui.lua` | `tui_{ascii_scroll,ascii_page,cjk_page,ts_page}` | ns/frame through a real pty + TUI, plus **write syscalls and bytes written per frame** |
| `bench_input.lua` | `latency_{plain,ts_stc}`, `bulk_input_ts_stc` | ns per keystroke, key -> redraw -> `flush` round trip (median, p95, p99) |
| `bench_rpc.lua` | `set_lines_100k`, `get_lines_100k`, `set_lines_100k_inproc` | ns for a 100k-line payload; lines/s and MB/s |
| `bench_micro.lua` | `vimscript_funcall_1e6`, `vimscript_map_1e6`, `lua_api_call_1e6`, `ts_iter_captures` | ns total / ns per iteration |

`scroll` is Ctrl-E one line at a time (incremental: `grid_scroll` plus one
`grid_line`). `page` jumps far enough that no screen row survives the diff and
pins it with `zt`, so every row is re-emitted -- the full-frame case.

## Methodology

* Median of 9 runs for the micro benchmarks, median of 5 for the heavy ones;
  min/max and relative standard deviation (`rsd_pct`) are recorded with every
  number so a noisy run is visible rather than silently averaged away.
* Benchmarks never run in parallel -- with each other or with a build.
* Timing is taken by the *child's* clock around the workload wherever the
  client could otherwise become the bottleneck (redraw, micro, TUI); the
  latency benchmark deliberately measures the full client-observed round trip,
  because that is what a keystroke costs.
* The corpus is generated deterministically by `corpus/gen_corpus.lua` (LCG
  seeded to a constant), so every machine and every wave measures identical
  input. The generated files are not committed.
* Output is JSONL on stdout (one object per case) and a human line on stderr.

## Syscall counting

`dtruss` needs root on macOS and non-interactive `sudo -n` is unavailable on
this machine, so `bench_tui.lua` counts syscalls by interposing them with
`DYLD_INSERT_LIBRARIES` (`syscount.c`, built on demand into `perf/out/`). It
counts `write`, `writev`, `read`, `readv`, `kevent`, `poll`, `select`,
`sendto`, and total bytes written; counts are differenced against a
zero-iteration run so startup and the initial paint drop out.

`ioctl` is deliberately *not* interposed: it is variadic, and replacing a
variadic function with a fixed-arity one breaks the arm64 varargs ABI (it
crashes on entry).

Interposition requires SIP to be disabled (it is, on this machine) because the
nvim binary is signed with the hardened runtime. If a future binary refuses
injection, re-sign a *copy* ad-hoc (`codesign -f -s - copy-of-nvim`) and point
the benchmark at the copy; the code is unchanged by re-signing.

## Files

    run_all.sh            orchestrator: facts + all benchmarks + summary table
    lib/bench.lua         stats, JSONL emission, corpus/paths, git SHA
    lib/client.lua        msgpack-RPC client with byte/UI-event counters
    bench_*.lua           the benchmarks
    tui_workload.lua      workload executed inside the pty-attached child
    syscount.c            DYLD interposer for syscall counts
    corpus/gen_corpus.lua deterministic corpus generator (output gitignored)
    out/                  results, built dylib (gitignored)
