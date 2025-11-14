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

1. [ ] Reconfirm all instructions/constraints before touching backlog item #2.
2. [ ] Reload ./.agents/PLAN.md and vertex memory so both reflect the new plan.
3. [ ] Capture git status/branch context before starting the next implementation.
4. [ ] Restate backlog item #2 requirements (skip overlay recomposition when content is unchanged) with success criteria.
5. [ ] Inventory current overlay data structures (grid metadata, comp_row_dirty, comp_dirty ranges) for reuse.
6. [ ] Audit overlay creation/update paths (popupmenu, float windows, diagnostics, LSP) to identify where content dirtiness can be signaled.
7. [ ] Design an overlay content epoch/hash that persists across scrolls/resizes so we can detect truly static overlays.
8. [ ] Plan API hooks or helper functions to mark overlays dirty/clean when buffers or extmarks change.
9. [ ] Extend `nvim__stats()` (or similar debug hook) to report overlay skip/dirty counters per overlay for observability.
10. [ ] Outline tracing/logging needed to validate skip decisions during development/testing.
11. [ ] Draft unit-test coverage (C tests) for the new overlay dirtiness helpers/metrics.
12. [ ] Draft functional UI tests (screen specs) that keep overlays static while base grid scrolls, ensuring skips trigger.
13. [ ] Define the performance instrumentation/benchmark plan to measure CPU savings after the change.
14. [ ] List the verification suites that must run before/after implementation (`make unittest`, compositor UI specs, `ninja -C build lint`).
15. [ ] Implement the content-dirty plumbing, metrics updates, and tests.
16. [ ] Summarize outcomes, update documentation/Notes, and sync plan/memory after the work is complete.

# Notes

- Reverted commits `bd6dde201372`, `d1e23377e14f`, and `c4f478a1fc22` (`feat(api): add batched buffer byte updates` and related commentstring fixes) after regression in "add batched buffer byte updates"; branch `optimize` now includes three corresponding revert commits.
    - Additionally restored `test/functional/treesitter/utils_spec.lua` to its pre-`84754715cfa2` state after confirming tree-sitter utility tests pass with the adjusted `_range.add_bytes` fix.
- clangd MCP queries currently lack compile_commands coverage (no symbol resolution); further analysis may require generating the build database.
- `ninja -C build lint` currently fails inside the `lintc-clint` phase: `clint.py` reports "Function attribute line should have 2-space indent" for `src/nvim/tui/tui.c:179`. The failure is captured in `/tmp/lint_run.log`; we need to either fix the indentation or carry the exception until upstream style guidance changes.
- Stylua/luacheck passes locally; the remaining backlog work shifts to backlog item #2 (skip recomposition when overlay content is unchanged). Proposed subtasks:
    1. Extend overlay grid metadata with an explicit "content dirty" epoch/hash that survives scrolls so we can detect when a floating window truly changed.
    2. Plumb overlay dirtiness notifications from buffer/window APIs (extmark, popup, LSP, UI events) into the compositor so skip decisions have authoritative data.
    3. Teach `nvim__stats()` (or a new debug hook) to report overlay skip/dirty counters per overlay so regressions are visible.
    4. Add functional coverage (UI screen tests) where overlay contents stay static while the base grid scrolls, ensuring skip logic holds across multiple event sources.
- Verification matrix before/after tackling backlog item #2: `make unittest`, `TEST_FILE=test/functional/ui/compositor_prune_spec.lua make functionaltest-lua`, `ninja -C build lint`, and a targeted multigrid UI spec to ensure overlay skip counters still increment.
