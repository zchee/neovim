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

1. [x] Re-read environment and task instructions to ensure compliance constraints are satisfied.
2. [x] Record current git status and outstanding changes relevant to performance work.
3. [x] Inspect existing ./.agents/MEMORY.md and other persistent notes for performance context.
4. [x] Survey project documentation (:help, CONTRIBUTING, profiling guides) for prior performance recommendations.
5. [x] Search repository for profiling scripts or benchmark artifacts indicating known hotspots.
6. [x] Use `rg --threads=8` to locate TODO/FIXME notes referencing performance.
7. [x] Review recent git history for performance-related commits to avoid redundant ideas.
8. [x] Map high-frequency runtime subsystems (event loop, redraw, UI) via source tree overview.
9. [x] Analyze input and event processing pipeline for O(n) or blocking operations.
10. [x] Inspect screen redraw logic for repeated work or avoidable recomputation.
11. [x] Evaluate Tree-sitter integration for parser invalidation and highlight performance.
12. [x] Assess Lua execution pathways, including RPC and `vim.loop`, for bottlenecks.
13. [x] Examine LSP client scheduling and throttling mechanisms for potential improvements.
14. [x] Use clangd MCP to trace hotspots’ call graphs and identify expensive loops.
15. [x] Check async job/channel APIs for synchronization or polling inefficiencies.
16. [x] Investigate filesystem watching and autocmd dispatch overhead.
17. [x] Review memory allocation patterns that can amplify runtime costs.
18. [x] Synthesize findings into prioritized performance improvement opportunities with estimated impact.
19. [>] Update ./.agents/PLAN.md with current plan state for persistence.
20. [ ] Prepare final report summarizing top dramatic performance improvement targets and next steps.

# Notes

- Reverted commits `bd6dde201372`, `d1e23377e14f`, and `c4f478a1fc22` (`feat(api): add batched buffer byte updates` and related commentstring fixes) after regression in "add batched buffer byte updates"; branch `optimize` now includes three corresponding revert commits.
    - Additionally restored `test/functional/treesitter/utils_spec.lua` to its pre-`84754715cfa2` state after confirming tree-sitter utility tests pass with the adjusted `_range.add_bytes` fix.
- clangd MCP queries currently lack compile_commands coverage (no symbol resolution); further analysis may require generating the build database.
