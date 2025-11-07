# Knowledge
- Terminfo optimizations: Previously implemented caching for zero-parameter terminfo capabilities in `src/nvim/tui/tui.c` and helper `terminfo_is_parametric` in `src/nvim/tui/terminfo.c`, plus unit coverage.
- TUI flush path: Optimized `flush_buf` to attempt `uv_try_write` before `uv_write`, avoiding needless event-loop iterations when writes complete synchronously.
- Performance hotspots: Profiling highlighted repeated `ml_find_line_or_offset()` calls, synchronous buffer-update callbacks, and `win_line()` recomputation as dominant costs during heavy edits; proposed mitigations include marktree byte-offset caching, batched extmark notifications, and line-render caching.
- Treesitter regressions: Functional tests such as `test/functional/lua/comment_spec.lua` fail even when the marktree byte cache is disabled. Failures show commentstring metadata not being applied (`-- print(1)` vs expected `"print(1)`), indicating an upstream issue in Treesitter comment handling (likely `vim.treesitter.get_node_text` / `_range.add_bytes` pipeline) that blocks cache reintroduction.
- Marktree cache state: Prior attempts to reintroduce the cache exposed tricky invalidation semantics; unit tests can be satisfied but functional regressions persist until Treesitter issues are resolved.
- Extmark splice path still recomputes absolute byte offsets through `ml_find_line_or_offset()` on every edit despite the cache helpers in `src/nvim/marktree.c:90-178`; caching remains gated on reliable invalidation triggered from `extmark_splice`/`marktree_splice` (`src/nvim/extmark.c:480-620`).
- Added `marktree_alloc`/`marktree_free` helpers so unit tests can obtain a correctly sized `MarkTree *` from C rather than relying on LuaJIT parsing; byte-cache specs now cover intra-line edits, deletions, and insertions to guard the splice logic.
- Buffer update and decoration providers (`src/nvim/buffer_updates.c:265-360`, `src/nvim/decoration_provider.c:33-200`) rely on high-frequency `nlua_call_ref` crossings, amplifying latency for heavy edits.
- `win_line()` rendering (`src/nvim/drawline.c:1040-1220`) remains a monolithic hot loop with repeated syntax and decoration setup on every redraw; incremental caching opportunities (virtual text, colorcolumn, decoration providers) are largely untapped.
- Treesitter Lua shims still funnel node-text extraction through `nvim_buf_get_text` (`runtime/lua/vim/treesitter.lua:220-264`), making capture-heavy queries CPU-bound; addressing this unblocks marktree byte caching work.
- TUI write path (`src/nvim/tui/tui.c:2586-2644`) benefits from `uv_try_write` but continues to flush whole buffers and spin `uv_run` when partial writes occur, leaving room for batching/flow-control improvements.
- Channel event scheduling (`src/nvim/channel.c:693-756`) processes each msgpack payload via per-channel multiqueue callbacks; batching or arena reuse could ease RPC throughput bottlenecks.

# Plan
1. Stabilize Treesitter range metadata: reproduce the commentstring failure, patch the `_range.add_bytes`/`get_node_text` path to avoid extra `nvim_buf_get_text` work, and land regression coverage.
2. Reintroduce marktree byte caching with explicit invalidation hooks fed from `extmark_splice`/`buf_updates_send_splice`, ensuring unit + functional coverage for insert/delete/move sequences.
3. Prototype batching APIs for buffer/decoration callbacks to cut `nlua_call_ref` frequency, starting with opt-in aggregated `on_lines` payloads and per-window decoration ranges.
4. Investigate `win_line()` incremental redraw: measure syntax/decor setup costs, experiment with retaining prepared state across lines, and validate against visual regressions.
5. Profile TUI and msgpack output during high-frequency redraws, then prototype buffered flush/queue coalescing to reduce `uv_run` churn and per-message allocations.

# Suggested Steps
1. Run `TEST_FILE=test/functional/lua/comment_spec.lua make functionaltest-lua` to capture logs, instrument `runtime/lua/vim/treesitter.lua` to log ranges, and verify commentstring metadata flow.
2. Draft a minimal reproduction (Lua snippet) invoking `vim.treesitter.query.get_node_text` with metadata to confirm failures without the entire suite.
3. Prototype fixes in `_range.lua` / `treesitter.lua`, add unit/functional coverage for the commentstring scenarios, and rerun targeted tests.
4. Reintroduce marktree byte-cache logic with updated tests once Treesitter regressions are resolved, followed by complete test runs and performance validation.
