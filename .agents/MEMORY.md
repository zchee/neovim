# Knowledge
- Implemented terminfo sequence caching in `src/nvim/tui/tui.c`, reducing repeated `terminfo_fmt` calls for zero-parameter capabilities. Added helper `terminfo_is_parametric` in `src/nvim/tui/terminfo.c` with unit coverage.
- Optimized TUI flush path to attempt `uv_try_write` before falling back to `uv_write`, avoiding unnecessary `uv_run` invocations when writes complete synchronously.
- Unit target: `TEST_FILE=test/unit/terminfo_spec.lua make unittest`

# Plan
1. Verify new flush behaviour on different platforms (macOS pipes, Linux, Windows console) to ensure the `uv_try_write` fallback covers all cases.
3. After validating, consider extending caching to cursor visibility helpers used in `flush_buf_start`/`flush_buf_end`, which still run through `terminfo_fmt`.
