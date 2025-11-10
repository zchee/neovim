# Knowledge
- Updated `vim._comment.get_commentstring` so it loads filetype `commentstring`s on demand and consults Tree-sitter injection metadata; `ts_parser:invalidate(true)` plus `_get_injections(true, {})` ensures injected Lua regions expose their own language tree even when the parser was started earlier.
- After pruning debug instrumentation, `TEST_FILE=test/functional/lua/comment_spec.lua make functionaltest-lua` now passes (all nine injection scenarios succeed). Manual headless repros confirm single-line toggles inside injected Lua use `--`, while multi-line block toggles still follow the first-line Vim commentstring as expected.

# Plan
1. Load ./.agents/MEMORY.md to restore prior knowledge and confirm instruction alignment.
2. Capture current git status to understand workspace changes impacting comment tests.
3. Review runtime/lua/vim/_comment.lua focusing on get_commentstring fallback behavior.
4. Review test/functional/lua/comment_spec.lua to align expectations with runtime behavior.
5. Collect and inspect instrumentation logs (e.g., /tmp/comment_debug.log, /tmp/nvim_comment_parts.log).
6. Verify parser child tree enumeration for heredoc injections in the functional test harness.
7. Prototype Range6 containment checks against LanguageTree children to validate language detection.
8. Determine optimal language-selection strategy (child traversal vs included_regions) for get_commentstring fallback.
9. Draft concrete code changes to update get_commentstring fallback to choose deepest language with commentstring.
10. Adjust toggle_lines/operator/current-line helpers to regroup regions by commentstring without duplication.
11. Remove or gate temporary instrumentation to keep runtime and tests clean.
12. Run TEST_FILE=test/functional/lua/comment_spec.lua make functionaltest-lua with required PATH adjustments.
13. Analyze any remaining failures, refine commentstring logic, and iterate.
14. Re-run targeted test until all comment_spec assertions pass.
15. Run minimal regression checks (e.g., comment_injection_min_spec.lua) to ensure no regressions.
16. Review broader codebase for related commentstring usage needing updates.
17. Document findings and updates back into ./.agents/MEMORY.md for persistence.
18. Summarize results and implications for user, including performance considerations unlocked by fixes.
19. Assess next directions for overall performance investigation per original request.
20. Prepare for transition to subsequent tasks or follow-up queries once comment issue resolved.
