# vfox-nim

Fast and reliable Nim version management for [mise](https://mise.jdx.dev/) and [vfox](https://vfox.dev/). Supports Windows, macOS, and Linux, on amd64, x86 and arm64.

[![CI](https://github.com/elijahr/vfox-nim/actions/workflows/test.yml/badge.svg)](https://github.com/elijahr/vfox-nim/actions/workflows/test.yml)
[![Latest release](https://img.shields.io/github/v/release/elijahr/vfox-nim)](https://github.com/elijahr/vfox-nim/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features

- **Fastest method per platform** — automatically selects the quickest installation path for your OS and architecture.
- **Four-level install strategy** — for stable versions, tries official binaries → exact nightly match → generic nightly builds → build from source.
- **Cross-platform** — Linux, macOS, and Windows on amd64, x86, and arm64, including the full toolchain (Nim compiler, Nimble package manager, and tools).
- **Windows-native and CI-verified** — fully supported with the unit, mise-integration, and vfox-integration suites running green on `windows-latest`.
- **Configurable install method** — choose `auto`, `binary`, or `source` to control how versions are installed.
- **Shared `~/.nimble`** — does not set `NIMBLE_DIR`, so Nimble uses the shared `~/.nimble` directory, matching a standard Nim install.

For platforms without official binaries (macOS, Linux ARM), the plugin uses Nim's nightly build infrastructure, which provides pre-built binaries for multiple platforms, often matching stable release versions.

| Platform    | Official Binaries | Nightly Builds | Source Build | Install Time |
| ----------- | :---------------: | :------------: | :----------: | ------------ |
| Linux x64   |        ✅         |       ✅       |      ✅      | ~30s         |
| Linux x32   |        ✅         |       ✅       |      ✅      | ~30s         |
| Linux ARM64 |        ❌         |       ✅       |      ✅      | ~60s         |
| Linux ARMv7 |        ❌         |       ✅       |      ✅      | ~60s         |
| Windows x64 |        ✅         |       ✅       |      ❌      | ~30s         |
| Windows x32 |        ✅         |       ✅       |      ❌      | ~30s         |
| macOS x64   |        ❌         |       ✅       |      ✅      | ~60s         |
| macOS ARM64 |        ❌         |       ✅       |      ✅      | ~60s         |

> **Windows.** Fully supported and CI-verified: the unit, mise-integration, and
> vfox-integration suites run green on `windows-latest` (a real `nim` install
> end-to-end) and the Windows legs are blocking. The one exception is the
> source-build method — `auto` selects the prebuilt binary on Windows (see the
> Windows note under Installation Method).

## Quick Start

### With mise

```bash
mise plugin install nim https://github.com/elijahr/vfox-nim

# Install latest Nim
mise install nim@latest

# Or install a specific version
mise install nim@2.0.0

# Set as global default
mise use -g nim@latest
```

### With vfox

```bash
vfox add --source https://github.com/elijahr/vfox-nim/archive/refs/heads/main.zip --alias nim

# Install latest Nim
vfox install nim@latest

# Set as global default
vfox use -g nim@latest
```

<!-- TODO: demo GIF/asciinema of `mise install nim@2.2.0`. Record with vhs or asciinema,
     drop the asset at docs/demo.gif, and replace this comment with ![demo](docs/demo.gif) -->

A real install on Linux x64 finishes in about 30 seconds:

```console
$ mise install nim@2.2.0
mise nim@2.2.0  downloading nim-2.2.0-linux_x64.tar.xz
mise nim@2.2.0  installing nim-2.2.0-linux_x64.tar.xz
mise nim@2.2.0  Installed Nim 2.2.0 via official binary
$ mise exec nim@2.2.0 -- nim --version
Nim Compiler Version 2.2.0 [Linux: amd64]
```

> **Installation paths / registry.** vfox-nim is a third-party plugin; mise and vfox
> do not reference it, and neither registry has a `nim` entry today. You always
> install it explicitly from `elijahr/vfox-nim` as shown above, under a local name of
> your choice. The bare registry forms (`mise plugins install nim` with no URL, or
> `vfox add nim` with no `--source`) do NOT install this plugin — they resolve through
> the registries to a different plugin, or fail.

## Installing versions

```bash
# Latest stable release
mise install nim@latest

# A specific version
mise install nim@2.2.0

# Newest patch within a series
mise install nim@2.2          # newest 2.2.x
mise install nim@2            # newest 2.x

# Nim's development branch — fetched as a prebuilt nightly binary when one exists
# for your platform, otherwise built from source
mise install nim@ref:devel

# Any Nim branch, or a specific commit
mise install nim@ref:version-2-2
mise install nim@ref:1a2b3c4
```

`ref:` specs use a prebuilt nightly binary when one is available for your platform, and
otherwise build from source. A bare branch name (`mise install nim@devel`) also works, but
always builds from source.

Pin a project with a version file — the plugin reads `.nim-version`, and mise's own
`mise.toml` / `.tool-versions` work too:

```bash
echo "2.2.0" > .nim-version
mise install            # installs the version named in .nim-version
```

> **GitHub API rate limits.** vfox-nim queries the GitHub API to resolve versions and
> nightly builds. Behind a shared IP or in CI, set `GITHUB_TOKEN` to avoid rate-limit
> errors (`export GITHUB_TOKEN=...`, or `${{ secrets.GITHUB_TOKEN }}` in Actions).

vfox accepts the same specs: `vfox install nim@2.2.0`, `vfox install nim@ref:devel`, and so on.

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

### Coming from asdf's `nim` plugin

vfox-nim is an independent alternative to asdf's `nim` plugin
([`asdf-community/asdf-nim`](https://github.com/asdf-community/asdf-nim)) written by
the same author, intended as a successor for use with mise and vfox. (A separate
[`mise-plugins/mise-nim`](https://github.com/mise-plugins/mise-nim) plugin exists; it
is a fork of `asdf-nim` that runs under mise's legacy asdf-bash-plugin shim, not a
native vfox plugin.) If you switch from asdf-nim to vfox-nim, two differences matter:

- **`NIMBLE_DIR` is no longer set per-version.** asdf-nim exports
  `NIMBLE_DIR=<install>/nimble`, so your globally-installed nimble packages live
  inside each Nim version's install directory. vfox-nim leaves `NIMBLE_DIR` unset
  (shared `~/.nimble`, matching `choosenim`). After switching, reinstall your global
  nimble tools (`nimble install -g <pkg>`) so they resolve from `~/.nimble`; the old
  per-version packages are not deleted, just no longer on `PATH`. To keep the old
  layout, set `NIMBLE_DIR` yourself — the plugin honors it.
- **Switching plugins is a reinstall, not an update.** `mise plugins update` pulls
  the installed plugin's own Git remote; it does not move you between different
  plugins. asdf-nim is an asdf-backend plugin and vfox-nim is a vfox-backend plugin,
  so switch with `mise plugin uninstall nim && mise plugin install nim https://github.com/elijahr/vfox-nim`
  (for vfox: `vfox remove nim`, then re-add per the Quick Start).

## GitHub Actions

Install Nim through mise + vfox-nim in a workflow. This runs on Linux, macOS, and Windows:

```yaml
name: CI
on: [push, pull_request]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Set up mise
        uses: jdx/mise-action@v2

      - name: Install Nim via vfox-nim
        shell: bash
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} # avoid GitHub API rate limits
        run: |
          mise plugin install nim https://github.com/elijahr/vfox-nim
          mise use nim@2.2.0
          mise exec -- nim --version

      # On Windows, Nim and Nimble are dynamically linked against OpenSSL and PCRE.
      # Install Nim's DLL bundle (plus a CA bundle for HTTPS) so `nimble` works.
      - name: Install Nim runtime DLLs (Windows)
        if: runner.os == 'Windows'
        shell: pwsh
        run: |
          $ProgressPreference = 'SilentlyContinue'
          Invoke-WebRequest https://nim-lang.org/download/dlls.zip -OutFile dlls.zip
          Expand-Archive dlls.zip -DestinationPath "$env:GITHUB_WORKSPACE\nim-dlls" -Force
          Add-Content $env:GITHUB_PATH "$env:GITHUB_WORKSPACE\nim-dlls"
          Invoke-WebRequest https://curl.se/ca/cacert.pem -OutFile "$env:GITHUB_WORKSPACE\cacert.pem"
          Add-Content $env:GITHUB_ENV "SSL_CERT_FILE=$env:GITHUB_WORKSPACE\cacert.pem"

      - name: Build and test
        shell: bash
        run: mise exec -- nimble test
```

`jdx/mise-action` installs and activates mise. The Windows DLL step mirrors what
[`nim-lang/setup-nimble-action`](https://github.com/nim-lang/setup-nimble-action) does —
without those DLLs, `nimble` operations that use HTTPS fail with missing-DLL errors; skip
the step if your build never invokes nimble's networking.

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
