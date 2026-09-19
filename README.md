# vfox-nim

Fast, cross-platform Nim version manager plugin for [mise](https://mise.jdx.dev/) and [vfox](https://vfox.dev/).

[![CI](https://github.com/elijahr/vfox-nim/actions/workflows/test.yml/badge.svg)](https://github.com/elijahr/vfox-nim/actions/workflows/test.yml)
[![Latest release](https://img.shields.io/github/v/release/elijahr/vfox-nim)](https://github.com/elijahr/vfox-nim/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Overview

`vfox-nim` installs and manages Nim SDKs on Linux, macOS, and Windows. It downloads prebuilt binaries whenever possible—including on Apple Silicon and Linux ARM—and falls back to compiling from source when a binary is unavailable.

### Key Capabilities

- **Fast binary downloads**: Automatically matches stable releases against prebuilt official releases or matching official nightlies.
- **Apple Silicon and ARM support**: Provides prebuilt binaries for macOS ARM64 and Linux ARM, avoiding lengthy source compilations.
- **Out-of-the-box compiler module access**: Configures `path = "$nim"` in `config/nim.cfg` so packages that import compiler internals (`import compiler/ast`) work immediately without extra compiler flags or redownloading Nim.
- **Full toolchain**: Installs `nim`, `nimble`, `nimsuggest`, `nimpretty`, and standard development tools.
- **Standard package sharing**: Leaves `NIMBLE_DIR` unset by default so Nimble shares packages in `~/.nimble` across toolchains, preserves CLI tools across updates, and supports project-local `nimbledeps` and Atlas.
- **Install method control**: Choose between `auto` (default), `binary` (prebuilt only), or `source` (compile from source).

---

## Platform Support

| Platform                        |   Prebuilt Binaries   | Source Build |  CI Coverage  |
| :------------------------------ | :-------------------: | :----------: | :-----------: |
| **Linux x86_64**                | ✅ Official & Nightly |      ✅      | Native runner |
| **Linux ARM64**                 |   ✅ Nightly match    |      ✅      | Emulated QEMU |
| **Linux ARMv7**                 |   ✅ Nightly match    |      ✅      | Emulated QEMU |
| **macOS Apple Silicon (arm64)** |   ✅ Nightly match    |      ✅      | Native runner |
| **macOS Intel (x86_64)**        |   ✅ Nightly match    |      ✅      | Native runner |
| **Windows x86_64**              | ✅ Official & Nightly |      ❌      | Native runner |

---

## Quick Start

### Using mise

Install Nim directly using mise's vfox backend:

```bash
# Install and set global default
mise use -g vfox:elijahr/vfox-nim@latest
```

Or register the plugin under the short name `nim`:

```bash
# Register plugin
mise plugin install nim https://github.com/elijahr/vfox-nim

# Install and activate latest stable Nim
mise use -g nim@latest
```

Verify your installation:

```bash
nim --version
nimble --version
```

### Using vfox

```bash
# Add plugin
vfox add --source https://github.com/elijahr/vfox-nim/archive/refs/heads/main.zip --alias nim

# Install and activate latest stable Nim
vfox install nim@latest
vfox use -g nim@latest
```

---

## Installing Versions

You can install specific releases, development branches, or exact commits:

```bash
# Latest stable release
mise install nim@latest

# Specific release version
mise install nim@2.2.8

# Partial version prefix (resolves to latest matching release)
mise install nim@2.2
mise install nim@2

# Nim development branch (uses prebuilt nightly if available, otherwise builds from source)
mise install nim@ref:devel

# Specific release branch or git commit
mise install nim@ref:version-2-2
mise install nim@ref:1a2b3c4
```

### Project Version Files

Pin the Nim version for your project with a `.nim-version` file:

```bash
echo "2.2.8" > .nim-version
mise install
```

mise also supports standard `mise.toml` and `.tool-versions` files.

> **Rate Limit Note**: The plugin queries the GitHub Releases API to resolve version tags and nightly binaries. In CI environments or behind shared NAT IPs, set `GITHUB_TOKEN` in your environment to prevent rate-limiting.

---

## Configuration

Control how the plugin installs Nim by setting `install_method`:

- **`auto`** (default): Uses official binaries first, falls back to matching nightlies, and compiles from source if no binary exists.
- **`binary`**: Prebuilt binaries only. Fails with an error if no prebuilt binary is available for your platform.
- **`source`**: Compiles Nim from source using C bootstrap sources (`build_all.sh` / `koch`). Not supported on Windows.

### Configuration Methods

In `mise.toml`:

```toml
[tools]
nim = "2.2.8"

[env]
_.nim = { install_method = "binary" }
```

Or via environment variable in your shell or CI workflow:

```bash
export NIM_INSTALL_METHOD="binary"
```

---

## Compiler Internals & Search Paths

Some Nim tools and libraries import compiler internal modules, such as:

```nim
import compiler/[ast, idents, parser, options]
```

By default in standard tarballs, the compiler sources reside at `$SDK/compiler`, but are not on Nim's default library search path. Previously, packages importing compiler internals would either fail or cause Nimble to clone the entire Nim repository (~1.5 GB) and recompile the compiler from scratch.

`vfox-nim` configures `path = "$nim"` in `config/nim.cfg` and creates a relative `lib/compiler` symlink on Unix during installation. Compiler modules resolve directly against the installed SDK out of the box, with no manual `--path` compiler flags required.

---

## Package Directory (`NIMBLE_DIR`) & Tool Management

This plugin intentionally leaves `NIMBLE_DIR` **unset**, defaulting to the shared `~/.nimble` directory.

### Why this benefits you:

1. **Persistent CLI Tools**: Binaries installed via `nimble install -g <package>` remain available in `~/.nimble/bin` when switching Nim versions.
2. **Project-Local Dependencies**: Nimble's automatic `nimbledeps` detection functions properly (it requires `NIMBLE_DIR` to be unset).
3. **Atlas Compatibility**: Works seamlessly with [Atlas](https://github.com/nim-lang/atlas) workspaces and local `_deps` configurations.
4. **Custom Overrides**: If you set `NIMBLE_DIR` in your shell, the plugin respects your setting.

---

## GitHub Actions Workflow

Here is a tested GitHub Actions workflow that installs Nim across Linux, macOS, and Windows:

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

      - name: Install Nim
        shell: bash
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          mise plugin install nim https://github.com/elijahr/vfox-nim
          mise use -g nim@2.2.8
          nim --version
          nimble --version

      # Windows requires runtime DLLs for HTTPS and SSL support in Nimble
      - name: Install Nim Windows runtime DLLs
        if: runner.os == 'Windows'
        shell: pwsh
        run: |
          $ProgressPreference = 'SilentlyContinue'
          Invoke-WebRequest https://nim-lang.org/download/dlls.zip -OutFile dlls.zip
          Expand-Archive dlls.zip -DestinationPath "$env:GITHUB_WORKSPACE\nim-dlls" -Force
          Add-Content $env:GITHUB_PATH "$env:GITHUB_WORKSPACE\nim-dlls"
          Invoke-WebRequest https://curl.se/ca/cacert.pem -OutFile "$env:GITHUB_WORKSPACE\cacert.pem"
          Add-Content $env:GITHUB_ENV "SSL_CERT_FILE=$env:GITHUB_WORKSPACE\cacert.pem"

      - name: Run Tests
        shell: bash
        run: nimble test
```

---

## Development

To contribute or run tests locally:

```bash
# 1. Trust the local mise configuration
mise trust

# 2. Link plugin to local development workspace
mise plugin link --force nim .

# 3. Run unit tests (busted)
mise run test-unit

# 4. Run static analysis and formatting checks
mise run lint
mise run format
```

---

## License

This project is licensed under the [MIT License](LICENSE).
