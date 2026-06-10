# vfox-nim

Fast and reliable Nim version management for [mise](https://mise.jdx.dev/) and [vfox](https://vfox.dev/).

## Features

Automatically selects the fastest installation method for your platform. For platforms without official binaries (macOS, Linux ARM), the plugin uses Nim's nightly build infrastructure which provides pre-built binaries for multiple platforms, often matching stable release versions.

| Platform    | Official Binaries | Nightly Builds | Source Build | Install Time |
| ----------- | :---------------: | :------------: | :----------: | ------------ |
| Linux x64   |        ✅         |       ✅       |      ✅      | ~30s         |
| Linux x32   |        ✅         |       ✅       |      ✅      | ~30s         |
| Linux ARM64 |        ❌         |       ✅       |      ✅      | ~60s         |
| Linux ARMv7 |        ❌         |       ✅       |      ✅      | ~60s         |
| Windows x64 |        ✅         |       ✅       |      ✅      | ~30s         |
| Windows x32 |        ✅         |       ✅       |      ✅      | ~30s         |
| macOS x64   |        ❌         |       ✅       |      ✅      | ~60s         |
| macOS ARM64 |        ❌         |       ✅       |      ✅      | ~60s         |

> **Windows.** The plugin logic supports Windows; Windows CI verification is
> deferred (the matrix legs are non-blocking this release). Linux and macOS are
> CI-verified.

- Configurable installation method (auto/binary/source)
- Includes Nim compiler, Nimble package manager, and tools

## Quick Start

### With mise

```bash
# Install the plugin directly from the Git URL (works today, no registry needed)
mise plugin install https://github.com/elijahr/vfox-nim

# Install latest Nim
mise install nim@latest

# Or install a specific version
mise install nim@2.0.0

# Set as global default
mise use -g nim@latest
```

### With vfox

```bash
# Install the plugin from the source archive (works today, no registry needed)
vfox add --source https://github.com/elijahr/vfox-nim/archive/refs/heads/main.zip --alias nim

# Install latest Nim
vfox install nim@latest

# Set as global default
vfox use -g nim@latest
```

> **Installation paths / registry.** The URL/source install commands above work
> immediately against this repository. The shorter registry-alias forms
> (`mise plugins install nim` and `vfox add nim`) become available only after a
> one-time registry submission (the mise registry for the mise alias; the
> version-fox registry for the vfox alias). The exact registry repository and
> submission process are confirmed during the release checklist, not asserted here.

## Configuration

The vfox-nim plugin supports custom configuration to control installation behavior.

### Installation Method

Control how Nim versions are installed. There are two ways to configure this:

#### Option 1: Via `mise.toml` (Recommended)

Use the `MiseEnv` hook to configure install method in your project's `mise.toml`:

```toml
[env]
_.vfox-nim = { install_method = "auto" }
```

#### Option 2: Via Environment Variable

Set the `VFOX_NIM_INSTALL_METHOD` environment variable directly:

```bash
# In your shell or CI environment
export VFOX_NIM_INSTALL_METHOD=binary

# Or in mise.toml
[env]
VFOX_NIM_INSTALL_METHOD = "binary"
```

**Valid values:**

| Value      | Behavior                                                                                                                         |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `"auto"`   | **(Default)** Try pre-built binaries first (official, then nightly), fall back to building from source if no binary is available |
| `"binary"` | **Only use pre-built binaries**. Installation will fail with an error if no binary is available for your platform                |
| `"source"` | **Only build from source**. Always downloads and compiles the source tarball                                                     |

**Examples:**

```toml
# Option 1: Via MiseEnv hook (recommended for per-project configuration)
[env]
_.vfox-nim = { install_method = "auto" }

# Option 2: Via environment variable (simple approach)
[env]
VFOX_NIM_INSTALL_METHOD = "binary"

# Both can be used together - environment variable takes precedence
```

**Common use cases:**

```toml
# Binary-only installations (useful for CI/CD to ensure fast installs)
[env]
VFOX_NIM_INSTALL_METHOD = "binary"

# Always build from source (useful for debugging or custom patches)
[env]
VFOX_NIM_INSTALL_METHOD = "source"

# Default behavior - try binaries first, fall back to source
# (no configuration needed, or explicitly set to "auto")
```

**Installation strategy by method:**

- **`auto`** (default): For stable versions, tries official binaries → exact nightly match → build from source. For ref versions, tries binaries → nightly builds → error.
- **`binary`**: Same as auto, but fails with error instead of falling back to source build.
- **`source`**: Immediately downloads source tarball and builds (stable versions only).

> **Windows note.** On Windows the plugin installs official prebuilt Nim binaries.
> Forcing a source compile (`VFOX_NIM_INSTALL_METHOD=source`) is **not supported on
> Windows**; `auto` correctly selects the binary install path there.

**Testing your configuration:**

```bash
# See what environment variables are set
mise env | grep VFOX_NIM

# Install a version to test the configuration
mise install nim@2.0.0

# Check the installation note
mise ls nim
```

### Nimble package directory (`NIMBLE_DIR`)

This plugin does **not** set `NIMBLE_DIR`. Nim therefore uses the shared
`~/.nimble` directory, matching the behavior of
[`choosenim`](https://github.com/nim-lang/choosenim) and a standard Nim install.
Leaving it unset means:

- A `NIMBLE_DIR` you set yourself (in your shell, `mise.toml` `[env]`, or CI) is
  respected — the plugin never overrides it.
- Nimble's project-local
  [`nimbledeps`](https://nim-lang.github.io/nimble/workflow.html#nimbledeps)
  auto-detection still works (it only activates when `NIMBLE_DIR` is unset).

Earlier versions pinned `NIMBLE_DIR` to a per-version `<install>/nimble` path
(inherited from `asdf-nim`). That polluted the managed install directory and lost
installed packages whenever a Nim version was reinstalled; it is no longer done.

## Development

```bash
# 1. Trust the repo's mise config (an untrusted mise.toml breaks every shimmed
#    command with "not trusted").
mise trust

# 2. Provision a durable Lua 5.1-ABI toolchain (LuaJIT + busted/luacheck) OUTSIDE
#    /tmp so it survives reboots. LuaJIT is the Lua 5.1-ABI interpreter the suite
#    runs green under (~0.5s). Install LuaJIT and luarocks first if absent:
#    `brew install luajit luarocks`.
luarocks --lua-version 5.1 --lua-dir "$(brew --prefix luajit)" \
  --tree "$HOME/.vfox-nim-rocks" install busted
luarocks --lua-version 5.1 --lua-dir "$(brew --prefix luajit)" \
  --tree "$HOME/.vfox-nim-rocks" install luacheck

# Link plugin for development
mise plugin link --force nim .

# Fast unit suite (Tiers I+II — mocked wiring + install-logic). The rocks-tree
# bin must be on PATH so `busted` resolves:
PATH="$HOME/.vfox-nim-rocks/bin:$PATH" mise run test-unit
# Equivalent direct invocation (set LUA_PATH/LUA_CPATH to the rocks tree first):
#   export LUA_PATH="$HOME/.vfox-nim-rocks/share/lua/5.1/?.lua;$HOME/.vfox-nim-rocks/share/lua/5.1/?/init.lua;./?.lua;./?/init.lua;;"
#   export LUA_CPATH="$HOME/.vfox-nim-rocks/lib/lua/5.1/?.so;;"
#   luajit "$HOME/.vfox-nim-rocks/bin/busted" spec/

# Install-smoke test (downloads and runs a real Nim toolchain over the network):
mise run test

# Lint + format. These run the pre-commit hooks. pre-commit's `luacheck` hook
# needs `luacheck` on PATH — it is NOT provided by mise.toml (which only pins
# stylua + actionlint). Install it into the durable rocks tree above and expose
# its bin, e.g.:
#   PATH="$HOME/.vfox-nim-rocks/bin:$PATH" mise run lint
# Without luacheck on PATH, commits fail with "Executable `luacheck` not found".
# Lint/format use the mise-pinned stylua 2.3.1 — always invoke via mise so CI and
# local agree (a system stylua may be a different version, e.g. 2.5.2):
mise run lint
mise run format

# Reproduce the Linux CI legs locally (Docker; macOS/Windows legs are not act-runnable):
act -j lua_tests                                      # Tier I+II Linux leg
act -j vfox_integration_test -s GITHUB_TOKEN=<token>  # Tier III Linux leg
```

## License

MIT
