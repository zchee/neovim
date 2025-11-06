# Knowledge
- Terminfo optimizations: Previously implemented caching for zero-parameter terminfo capabilities in `src/nvim/tui/tui.c` and helper `terminfo_is_parametric` in `src/nvim/tui/terminfo.c`, plus unit coverage.
- TUI flush path: Optimized `flush_buf` to attempt `uv_try_write` before `uv_write`, avoiding needless event-loop iterations when writes complete synchronously.
- Performance hotspots: Profiling highlighted repeated `ml_find_line_or_offset()` calls, synchronous buffer-update callbacks, and `win_line()` recomputation as dominant costs during heavy edits; proposed mitigations include marktree byte-offset caching, batched extmark notifications, and line-render caching.
- Treesitter regressions: Functional tests such as `test/functional/lua/comment_spec.lua` fail even when the marktree byte cache is disabled. Failures show commentstring metadata not being applied (`-- print(1)` vs expected `"print(1)`), indicating an upstream issue in Treesitter comment handling (likely `vim.treesitter.get_node_text` / `_range.add_bytes` pipeline) that blocks cache reintroduction.
- Marktree cache state: Prior attempts to reintroduce the cache exposed tricky invalidation semantics; unit tests can be satisfied but functional regressions persist until Treesitter issues are resolved.

# Plan
1. Diagnose Treesitter commentstring failures by instrumenting `vim.treesitter.get_node_text`, `_range.add_bytes`, and comment helpers to understand why metadata is ignored after recent batching/marktree changes.
2. Create minimal Lua/Treesitter reproductions outside the full functional suite to iterate quickly, then patch the offending range/offset logic (likely in `_range.lua` or metadata handling) and add regression tests.
3. Once Treesitter behavior is corrected, reapply marktree byte-cache improvements with a sound invalidation strategy, ensuring unit specs cover splices, insertions, deletions, and cache miss behavior.
4. Validate with `TEST_FILE=test/unit/marktree_spec.lua make unittest`, targeted functional subsets (Treesitter/comment specs, buffer updates), and finally full `make unittest` and `make functionaltest-lua`.

# Suggested Steps
1. Run `TEST_FILE=test/functional/lua/comment_spec.lua make functionaltest-lua` to capture logs, instrument `runtime/lua/vim/treesitter.lua` to log ranges, and verify commentstring metadata flow.
2. Draft a minimal reproduction (Lua snippet) invoking `vim.treesitter.query.get_node_text` with metadata to confirm failures without the entire suite.
3. Prototype fixes in `_range.lua` / `treesitter.lua`, add unit/functional coverage for the commentstring scenarios, and rerun targeted tests.
4. Reintroduce marktree byte-cache logic with updated tests once Treesitter regressions are resolved, followed by complete test runs and performance validation.
