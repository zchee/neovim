# Dramatic Performance Improvement Backlog

1. **Row/column pruning for visible overlays**
   - *Current bottleneck*: Even when an overlay (popup, floating window) only covers a small portion of the scrolled area, the compositor recomposes the entire span/width, wasting CPU on untouched cells.
   - *Why it helps*: Cropping redraw work to the true overlap slashes per-scroll CPU and reduces cache churn.
   - *Planned work*: Extend the overlap computation prototype, skip composition outside the covering grid, and reuse the popup guard infrastructure for other grids.

2. **Skip recomposition when overlay content is unchanged**
   - *Current bottleneck*: The compositor redraws overlays on every scroll even when the overlay grid’s contents haven’t changed.
   - *Why it helps*: Avoiding redundant recompositions removes huge amounts of repeated work during static overlays.
   - *Planned work*: Track overlay dirtiness (e.g., item changes in popup menus) and bypass recomposition when the grid is unchanged.

3. **Batch compositor updates within an event tick**
   - *Current bottleneck*: Rapid inputs cause multiple scroll/redraw calls in a single loop iteration, leading to duplicate compositor work.
   - *Why it helps*: Merging updates ensures each frame processes scrolls once, lowering redundant composition.
   - *Planned work*: Queue scroll/overlay changes and commit them at the end of the loop, coalescing repeated operations.

4. **Cache overlay coverage state**
   - *Current bottleneck*: On every scroll, overlay bounds are recomputed from scratch even when the overlay hasn’t moved.
   - *Why it helps*: Reusing precomputed coverage avoids repeated intersection math and speeds up the hot path.
   - *Planned work*: Cache row/column bounds per overlay while static, and invalidate the cache when the overlay moves or resizes.

5. **Offload heavy overlays to offscreen buffers**
   - *Current bottleneck*: Large floating windows require recomputing chars/attrs on every frame.
   - *Why it helps*: Rendering once offscreen reduces per-frame work to a simple blit.
   - *Planned work*: Experiment with pre-rendering diagnostics or status panels into secondary buffers and compositing them like the terminal grid.

6. **Tree-sitter/syntax invalidation pruning**
   - *Current bottleneck*: Scrolls trigger broad syntax invalidation, feeding unnecessary highlights to the compositor.
   - *Why it helps*: Narrowing syntax work to only the visible nodes reduces the pipeline pressure before the compositor even starts.
   - *Planned work*: Audit Tree-sitter range invalidation and limit it to nodes intersecting the viewport.

7. **Lua/RPC batching**
   - *Current bottleneck*: Plugins and LSP send multiple UI updates per keystroke, causing a flood of redraws.
   - *Why it helps*: Batching cuts the number of redraw-triggering events, keeping the compositor idle more often.
   - *Planned work*: Batch diagnostics/log updates and explore aggregating UI-affecting Lua callbacks.

# Knowledge

- Mapped profiling-related TODOs in input, UI compositor, Tree-sitter highlighter, LSP changetracking, channel I/O, and filesystem watcher layers for follow-up performance work.
- Noted recent perf commits touching extmarks, TUI terminfo, events, highlight, API, and scheduler behavior to avoid duplicate investigations.

# Plan

1. [x] Reconfirm all user and developer instructions, constraints, and recent context for the current task.
2. [x] Load ./.agents/PLAN.md to synchronize persistent planning state.
3. [ ] Capture current git status and branch context to establish baseline.
4. [ ] Inspect recent modifications in src/nvim/ui_compositor.c tied to overlay dirtiness and skip logic.
5. [ ] Review corresponding declarations in src/nvim/ui_compositor.h for alignment with implementation.
6. [ ] Survey src/nvim/grid.c changes to understand dirty-row propagation.
7. [ ] Check src/nvim/grid_defs.h for structural or initialization changes tied to comp_row_dirty.
8. [ ] Assess src/nvim/api/vim.c updates exposing overlay skip metrics.
9. [ ] Identify other touched files (e.g., marktree, tui) for potential side effects on tests.
10. [ ] Use clangd MCP to trace dirty-marking helper call sites and ensure coverage.
11. [ ] Examine /tmp/unittest.log and related per-suite logs to characterize the unit test crash.
12. [ ] Run a focused unit test (e.g., TEST_FILE=typval) to reproduce failure with detailed output.
13. [ ] Determine whether compositor initialization happens during unit tests and locate crash source.
14. [ ] Instrument or add logging (temporary if needed) to isolate failing path, then remove after diagnosis.
15. [ ] Implement fix for dirty-row/compositor interaction causing unit-test crash.
16. [ ] Re-run make unittest to confirm resolution.
17. [ ] Verify targeted functional tests still pass after fix.
18. [ ] Document remaining lint issue (upstream Stylua) and summarize outcomes for the user.

# Notes

- Reverted commits `bd6dde201372`, `d1e23377e14f`, and `c4f478a1fc22` (`feat(api): add batched buffer byte updates` and related commentstring fixes) after regression in "add batched buffer byte updates"; branch `optimize` now includes three corresponding revert commits.
    - Additionally restored `test/functional/treesitter/utils_spec.lua` to its pre-`84754715cfa2` state after confirming tree-sitter utility tests pass with the adjusted `_range.add_bytes` fix.
- clangd MCP queries currently lack compile_commands coverage (no symbol resolution); further analysis may require generating the build database.
