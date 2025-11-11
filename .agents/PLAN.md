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
