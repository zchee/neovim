# Knowledge
- Implemented terminfo sequence caching in `src/nvim/tui/tui.c`, reducing repeated `terminfo_fmt` calls for zero-parameter capabilities. Added helper `terminfo_is_parametric` in `src/nvim/tui/terminfo.c` with unit coverage.
- Optimized TUI flush path to attempt `uv_try_write` before falling back to `uv_write`, avoiding unnecessary `uv_run` invocations when writes complete synchronously.
- Unit target: `TEST_FILE=test/unit/terminfo_spec.lua make unittest`
- Identified edit-path hotspots: repeated `ml_find_line_or_offset()` calls, synchronous buffer update callbacks, and `win_line()` recomputation dominate CPU during heavy edits or redraw storms. Proposed caching marktree leaf offsets, batching extmark notifications, and caching rendered lines to cut redraw and Lua bridge overhead.

# Plan
1. Verify new flush behaviour on macOS, Linux, and Windows consoles to ensure `uv_try_write` fallback covers all cases.
2. Extend terminfo caching to cursor visibility helpers used in `flush_buf_start`/`flush_buf_end`.
3. Prototype marktree leaf byte-offset caching and benchmark large-buffer edits.
4. Add instrumentation around `ml_find_line_or_offset()` and `win_line()` to measure hit rates and validate caching impact.
5. Design buffered event delivery for `buf_updates_send_splice()` so Lua hooks batch work instead of firing per edit.
6. After optimizations, reprofile screen redraws and refactor `win_line()` into skip-capable stages.

# Suggested Steps
1. Build a marktree leaf cache prototype, then run profiling/benchmarks on large buffers to capture before/after timings.
2. Instrument `ml_find_line_or_offset()` and `win_line()` usage inside the edit loop to capture current hot-path cost.
3. Sketch and implement a batched buffer-update dispatcher, migrating treesitter/LSP clients to the new path.
4. Reprofile redraw performance and restructure `win_line()` stages based on the new data.
