# vfox-nim

Fast and reliable Nim version management for [mise](https://mise.jdx.dev/) and [vfox](https://vfox.dev/). Supports Windows, macOS, and Linux, on amd64, x86 and arm64.

[![CI](https://github.com/elijahr/vfox-nim/actions/workflows/test.yml/badge.svg)](https://github.com/elijahr/vfox-nim/actions/workflows/test.yml)
[![Latest release](https://img.shields.io/github/v/release/elijahr/vfox-nim)](https://github.com/elijahr/vfox-nim/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features

- Picks the fastest install for your platform: official binaries, then nightly builds, then source.
- Runs on Linux, macOS, and Windows (x86_64, x86, arm64).
- Installs the full toolchain: Nim, Nimble, and tools.
- Force binary-only or source-only with `VFOX_NIM_INSTALL_METHOD`.
- Uses the shared `~/.nimble` (leaves `NIMBLE_DIR` unset, like a normal Nim install).

macOS and Linux ARM have no official Nim binaries, so the plugin uses Nim's nightly builds there, which often match stable releases.

| Platform    | Official Binaries | Nightly Builds | Source Build |
| ----------- | :---------------: | :------------: | :----------: |
| Linux x64   |        ✅         |       ✅       |      ✅      |
| Linux x32   |        ✅         |       ✅       |      ✅      |
| Linux ARM64 |        ❌         |       ✅       |      ✅      |
| Linux ARMv7 |        ❌         |       ✅       |      ✅      |
| Windows x64 |        ✅         |       ✅       |      ❌      |
| Windows x32 |        ✅         |       ✅       |      ❌      |
| macOS x64   |        ❌         |       ✅       |      ✅      |
| macOS ARM64 |        ❌         |       ✅       |      ✅      |

> CI runs real end-to-end installs on Linux x64, macOS x64/arm64, Windows x64, and
> emulated Linux arm64/armv7. The 32-bit rows and source builds on the non-x64
> platforms should work but aren't CI-covered. Source builds aren't available on Windows.

## Quick Start

### With mise

```bash
mise plugin install nim https://github.com/elijahr/vfox-nim

# Install latest Nim
mise install nim@latest

# Or install a specific version
mise install nim@2.2.0

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
mise nim@2.2.0  Official binary for linux/x86_64
$ mise exec nim@2.2.0 -- nim --version
Nim Compiler Version 2.2.0 [Linux: amd64]
```

## Installing versions

```bash
# Latest stable release
mise install nim@latest

# A specific version
mise install nim@2.2.0

# Partial versions (mise resolves these to the newest matching release)
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

Control how Nim is installed with the `install_method` option:

- `auto` (default): try official binaries, then nightly builds, then source.
- `binary`: pre-built binaries only; fail if none exists for your platform.
- `source`: always build from source. Not available on Windows.

Set it per project in `mise.toml`:

```toml
[env]
_.nim = { install_method = "binary" }
```

Or as an environment variable (works with both mise and vfox):

```bash
export VFOX_NIM_INSTALL_METHOD=binary
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
native vfox plugin.)

The main difference when switching: asdf-nim exports `NIMBLE_DIR=<install>/nimble`, so
your globally-installed nimble packages live inside each Nim version's install
directory. vfox-nim leaves `NIMBLE_DIR` unset (shared `~/.nimble`, matching
`choosenim`). After switching, reinstall your global nimble tools
(`nimble install -g <pkg>`) so they resolve from `~/.nimble`; the old per-version
packages aren't deleted, just no longer on `PATH`. To keep the old layout, set
`NIMBLE_DIR` yourself and the plugin honors it.

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
