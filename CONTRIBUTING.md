# Contributing

Welcome, and thank you for your interest in vfox-nim. Whether you are fixing a
typo, adding a test, reporting a bug, or proposing a new feature, your help
makes Nim version management better for everyone on mise and vfox.

vfox-nim is a small Lua-based plugin (`hooks/*.lua`) with a focused test suite.
You do not need to know much about the internals to make a useful contribution.

## Development Setup

Target: under 10 minutes. You need [mise](https://mise.jdx.dev/), plus LuaJIT
and luarocks for the Lua toolchain.

```bash
# Clone
git clone https://github.com/elijahr/vfox-nim.git
cd vfox-nim

# 1. Trust the repo's mise config. An untrusted mise.toml breaks every shimmed
#    command with a "not trusted" error.
mise trust

# 2. Install LuaJIT + luarocks if you don't have them.
brew install luajit luarocks            # macOS; use your package manager elsewhere

# 3. Provision a durable Lua 5.1-ABI toolchain (busted + luacheck) OUTSIDE /tmp
#    so it survives reboots. LuaJIT is the Lua 5.1-ABI interpreter the suite runs
#    green under (~0.5s).
luarocks --lua-version 5.1 --lua-dir "$(brew --prefix luajit 2>/dev/null || echo /usr)" \
  --tree "$HOME/.vfox-nim-rocks" install busted
luarocks --lua-version 5.1 --lua-dir "$(brew --prefix luajit 2>/dev/null || echo /usr)" \
  --tree "$HOME/.vfox-nim-rocks" install luacheck

# 4. Link the plugin for local development.
mise plugin link --force nim .
```

## Running Tests

The suite has two tiers: a fast mocked unit suite, and a slower install-smoke
test that downloads and runs a real Nim toolchain over the network.

```bash
# Fast unit suite (Tiers I+II — mocked wiring + install-logic).
# (`mise run test-unit` already puts the rocks-tree bin on PATH for busted.)
mise run test-unit

# Install-smoke test (real Nim install over the network).
mise run test
```

A passing unit run looks like `N successes / 0 failures / 0 errors` with exit
code 0.

To run a single spec file directly, set the rocks-tree paths and call `busted`:

```bash
export LUA_PATH="$HOME/.vfox-nim-rocks/share/lua/5.1/?.lua;$HOME/.vfox-nim-rocks/share/lua/5.1/?/init.lua;./?.lua;./?/init.lua;;"
export LUA_CPATH="$HOME/.vfox-nim-rocks/lib/lua/5.1/?.so;;"
luajit "$HOME/.vfox-nim-rocks/bin/busted" spec/smoke_spec.lua
```

You can also reproduce the Linux CI legs locally with
[`act`](https://github.com/nektos/act) (Docker required; the macOS and Windows
legs are not act-runnable):

```bash
act -j lua_tests                                      # Tier I+II Linux leg
act -j vfox_integration_test -s GITHUB_TOKEN=<token>  # Tier III Linux leg
```

## Code Style

Lua is formatted with `stylua` and linted with `luacheck`; GitHub Actions
workflows are linted with `actionlint`. These run via pre-commit hooks.

```bash
# Format (runs the pre-commit formatters).
mise run format

# Lint. The luacheck hook needs `luacheck` on PATH — it is NOT provided by
# mise.toml, so expose the durable rocks tree you installed above:
PATH="$HOME/.vfox-nim-rocks/bin:$PATH" mise run lint
```

Always invoke `stylua` via mise (mise pins version 2.3.1) so local and CI agree;
a system `stylua` may be a different version.

## Submitting a Pull Request

1. Fork the repository and create a branch from `main`.
2. Make your changes. Add or update tests if you are changing behavior.
3. Run the unit suite and the linter locally.
4. Open a pull request with a clear description of what you changed and why.

This project uses [Conventional Commits](https://www.conventionalcommits.org/)
for commit messages (e.g. `fix(arch): normalize_arch returns aarch64 for
linux/arm64`, `docs(README): ...`). Please follow that style for your commits.

## Types of Contributions

Code is not the only way to help. We welcome:

- Bug reports and feature requests (via the issue templates)
- Documentation improvements
- Test coverage additions, especially for platform/arch edge cases
- Platform support reports (confirming installs work on your OS/arch)

Thank you for contributing!
