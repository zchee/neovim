# Neovim Contributor Guide

A concise reference for contributing to Neovim. For comprehensive details, see [CONTRIBUTING.md](./CONTRIBUTING.md) and [:help dev-quickstart](https://neovim.io/doc/user/dev_tools.html#dev-quickstart).

## Quick Reference

```bash
make CMAKE_BUILD_TYPE=RelWithDebInfo  # Build with optimizations + debug info
make test                              # Run all tests
make format                            # Format C and Lua code
make lint                              # Run all linters
make lintcommit                        # Validate commit messages
```

## Project Structure

- **`src/nvim/`** - Core C source code
  - `api/` - RPC API implementation
  - `lua/` - Lua integration layer
  - `tui/` - Terminal UI
  - `eval/` - Vimscript/expression evaluation
  - `os/` - Platform-specific code
- **`test/`** - All tests
  - `functional/` - Lua functional tests (busted framework)
  - `unit/` - Unit tests
  - `old/testdir/` - Legacy Vim tests
- **`runtime/`** - Vim runtime files and Lua modules
- **`cmake.deps/`** - Third-party dependencies build configuration

## Build Commands

Neovim uses CMake with a Makefile wrapper. Install `ninja` for faster parallel builds (auto-detected).

```bash
# Development build (recommended)
make CMAKE_BUILD_TYPE=RelWithDebInfo

# Production build
make CMAKE_BUILD_TYPE=Release

# Install (default: /usr/local)
sudo make install

# Custom install location
make CMAKE_INSTALL_PREFIX=$HOME/local/nvim install

# Clean rebuild
make distclean && make
```

**Build types:** `Debug` (default, full debug info), `RelWithDebInfo` (optimized + debug), `Release` (full optimization).

## Testing

All PRs must include test coverage. Run tests before submitting.

```bash
make functionaltest-lua   # Lua functional tests (primary)
make unittest             # C unit tests
make oldtest              # Legacy Vim tests
make test                 # All tests

# Run specific test file
TEST_FILE=test/functional/ui/screen_spec.lua make functionaltest-lua

# Run with sanitizers (detect memory errors)
CC=clang make CMAKE_FLAGS="-DENABLE_ASAN_UBSAN=ON"
ASAN_OPTIONS=log_path=/tmp/nvim_asan ./build/bin/nvim
```

Test files use the [busted](https://github.com/lunarmodules/busted) framework. See [:help dev-test](https://neovim.io/doc/user/dev_tools.html#dev-test) for testing guidelines.

## Coding Style

### C Code

Based on Google C style with Neovim modifications:
- **Indentation:** 2 spaces (never tabs)
- **Line length:** 100 characters max
- **Pointer alignment:** Right (`int *ptr`)
- **Formatting tool:** Primary: `uncrustify` (via `make formatc`), Reference: `.clang-format`

```bash
make format       # Format all changed files (C + Lua)
make formatc      # Format C files only
make formatlua    # Format Lua files only
```

### Lua Code

Uses [StyLua](https://github.com/JohnnyMorganz/StyLua) formatter with configuration in `.stylua.toml`.

### Naming Conventions

- **Functions:** `snake_case` (C), `snake_case` (Lua public API)
- **Private Lua functions:** Prefix with `_` (e.g., `_parse_option`)
- **Macros:** `UPPER_SNAKE_CASE`
- **Types:** `PascalCase` (e.g., `ApiClient`)

## Commit Guidelines

Follow [conventional commits](https://www.conventionalcommits.org/) format. Validate with `make lintcommit`.

```
type(scope): subject

Problem:
Description of the issue being addressed.

Solution:
Description of how the issue is solved.
```

**Types:** `build`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `test`, `vim-patch`

**Examples:**
```
fix(lsp): prevent crash when server sends invalid response

Problem:
LSP client crashes if server sends malformed notification.

Solution:
Add validation for notification structure before processing.
```

```
feat(api): add nvim_win_set_config border style option
```

### Commit Message Rules

- **Subject:** Imperative mood ("Fix bug" not "Fixed bug"), under 72 chars
- **Scope:** Use specific components: `(lsp)`, `(treesitter)`, `(tui)`, `(api)`, etc.
- **Breaking changes:** Add `!` after type and `BREAKING CHANGE:` footer
- **Body:** Describe Problem/Solution for non-trivial changes

## Pull Request Guidelines

1. **Create draft PR** while working to avoid duplicate efforts
2. **Mark ready for review** when complete
3. **Include test coverage** - PRs without tests will not be merged
4. **Use feature branch** - Never commit directly to `master`
5. **Rebase workflow** - Keep commits clean, force-push after addressing reviews is fine
6. **Avoid cosmetic changes** in unrelated files

### PR Checklist

- [ ] Tests added/updated and passing locally
- [ ] Code formatted (`make format`)
- [ ] Linters pass (`make lint`)
- [ ] Commit messages follow conventions (`make lintcommit`)
- [ ] Documentation updated if needed

## Development Tips

### Faster Builds

```bash
# Install build accelerators (auto-detected)
sudo apt-get install ninja-build ccache  # Ubuntu/Debian
brew install ninja ccache                # macOS
```

### Lua Runtime Development

Changes to `runtime/lua/` require rebuilding or using `--luamod-dev`:

```bash
VIMRUNTIME=./runtime ./build/bin/nvim --luamod-dev
```

### Debugging

```bash
# Build with debug info
make CMAKE_BUILD_TYPE=Debug

# Run with debugger
gdb ./build/bin/nvim
lldb ./build/bin/nvim

# Check logs
nvim -c 'edit $NVIM_LOG_FILE'
```

### Code Navigation

Use [clangd](https://clangd.llvm.org/) LSP server with the provided `.clangd` configuration. Ignore noisy commits in blame:

```bash
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

## CI/CD

Every PR runs automated checks on GitHub Actions and Cirrus CI:
- **Compilation** with `-Werror` (warnings fail the build)
- **All tests** (functional, unit, old)
- **Linters** (format, style, commits, docs)
- **Sanitizers** (ASan, UBSan) for memory safety
- **Multiple platforms** (Linux, macOS, Windows, FreeBSD)

CI must pass before merge. See [.github/workflows/](https://github.com/neovim/neovim/tree/master/.github/workflows) for configuration.

## Additional Resources

- **Full guidelines:** [CONTRIBUTING.md](./CONTRIBUTING.md)
- **Developer docs:** [:help dev](https://neovim.io/doc/user/dev.html)
- **Testing guide:** [:help dev-test](https://neovim.io/doc/user/dev_tools.html#dev-test)
- **Doc style:** [:help dev-doc](https://neovim.io/doc/user/dev.html#dev-doc)
- **Style guide:** [:help dev-style](https://neovim.io/doc/user/dev_style.html)
- **API client dev:** [:help dev-api-client](https://neovim.io/doc/user/dev.html#dev-api-client)
- **UI development:** [:help dev-ui](https://neovim.io/doc/user/dev.html#dev-ui)
