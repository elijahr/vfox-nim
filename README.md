# vfox-nim

Fast, cross-platform Nim version manager plugin for [mise](https://mise.jdx.dev/) and [vfox](https://vfox.dev/).

[![CI](https://github.com/elijahr/vfox-nim/actions/workflows/test.yml/badge.svg)](https://github.com/elijahr/vfox-nim/actions/workflows/test.yml)
[![Latest release](https://img.shields.io/github/v/release/elijahr/vfox-nim)](https://github.com/elijahr/vfox-nim/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Overview

`vfox-nim` installs and manages Nim SDKs on Linux, macOS, and Windows. It downloads prebuilt binaries whenever possible—including on Apple Silicon and Linux ARM—and falls back to compiling from source when a binary is unavailable.

> [!NOTE]
> **Built-in `nim` vs `vfox-nim` in mise**:
> `mise` includes built-in support for official stable releases via `http:nim`.
>
> Use `vfox-nim` if you need:
> - **Nightly and development builds**: Direct support for `ref:devel` and exact Git commit hashes via `nim-lang/nightlies` without extra configuration.
> - **Automatic source compilation**: Automatically compiles Nim from source when prebuilts are unavailable (`install_method = "source"` or architecture fallbacks).
> - **Compiler module access**: Automatically configures `path = "$nim"` in `config/nim.cfg` so packages that import compiler internals (`import compiler/ast`) work out of the box without cloning the compiler repository.
> - **Standalone `vfox`**: Full support for the [VersionFox (vfox)](https://vfox.dev/) CLI on Linux, macOS, and Windows.

### Key Capabilities

- **Fast binary downloads**: Automatically matches stable releases against prebuilt official releases or matching official nightlies.
- **Apple Silicon and ARM support**: Provides prebuilt binaries for macOS ARM64 and Linux ARM, avoiding lengthy source compilations.
- **Out-of-the-box compiler module access**: Configures `path = "$nim"` in `config/nim.cfg` so packages that import compiler internals (`import compiler/ast`) work immediately without extra compiler flags or redownloading Nim.
- **Full toolchain**: Installs `nim`, `nimble`, `nimsuggest`, `nimpretty`, and standard development tools.
- **Standard package sharing**: Preserves standard Nimble package locations, CLI tools in `~/.nimble/bin`, project-local `nimbledeps`, and Atlas workspaces.
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

To use `vfox-nim`, specify the `vfox:` backend prefix:

```bash
# Install and set global default via vfox-nim
mise use -g vfox:elijahr/vfox-nim@latest
```

Alternatively, if you want the unqualified name `nim` in mise to resolve to `vfox-nim` instead of mise's built-in `http:nim` backend, register the plugin:

```bash
# Register plugin override
mise plugin install nim https://github.com/elijahr/vfox-nim

# Now `nim` resolves to vfox-nim
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

> [!TIP]
>
> ### Declarative Nim CLI Tools with `vfox-nimble`
>
> If you use tools like `nimlsp`, `c2nim`, `testament`, or `atlas`, consider adding the companion **[`vfox-nimble`](https://github.com/elijahr/vfox-nimble)** backend plugin.
>
> While `vfox-nim` manages the Nim compiler and core SDK, `vfox-nimble` lets you declare and pin Nim CLI packages directly in your `mise.toml`:
>
> ```toml
> [tools]
> "vfox:elijahr/vfox-nim" = "2.2.8"
> "nimble:c2nim" = "latest"
> "nimble:nimlsp" = "0.4.7"
> ```
>
> *(Or `nim = "2.2.8"` if registered as a plugin override via `mise plugin install nim`)*
>
> This keeps your developer tooling isolated, version-controlled, and reproducible across teammates and CI runners.

---

## Installing Versions

You can install specific releases, development branches, or exact commits:

### Using mise

```bash
# Latest stable release
mise install vfox:elijahr/vfox-nim@latest

# Specific release version
mise install vfox:elijahr/vfox-nim@2.2.8

# Partial version prefix (resolves to latest matching release)
mise install vfox:elijahr/vfox-nim@2.2
mise install vfox:elijahr/vfox-nim@2

# Nim development branch (uses prebuilt nightly if available, otherwise builds from source)
mise install vfox:elijahr/vfox-nim@ref:devel

# Specific release branch or git commit
mise install vfox:elijahr/vfox-nim@ref:version-2-2
mise install vfox:elijahr/vfox-nim@ref:1a2b3c4
```

> **Note**: If you registered `vfox-nim` via `mise plugin install nim https://github.com/elijahr/vfox-nim`, you can use `nim@...` (e.g. `mise install nim@ref:devel`) directly. Without the plugin registered, bare `nim@...` commands in mise use its built-in `http:nim` backend.

### Using vfox

```bash
# Latest stable release
vfox install nim@latest

# Specific release version
vfox install nim@2.2.8

# Development branch or commit
vfox install nim@ref:devel
vfox install nim@ref:1a2b3c4
```

### Project Version Files

In `mise.toml`, declare the tool using the `vfox:` prefix (or `nim` if registered via `mise plugin install`):

```toml
[tools]
"vfox:elijahr/vfox-nim" = "2.2.8"
```

If registered via `mise plugin install nim`, standard `.nim-version` and `.tool-versions` files are also supported:

```bash
echo "2.2.8" > .nim-version
mise install
```

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
"vfox:elijahr/vfox-nim" = "2.2.8"

[env]
_."vfox:elijahr/vfox-nim" = { install_method = "binary" }
# Or if registered as `nim`:
# _.nim = { install_method = "binary" }
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

## Companion Plugin: `vfox-nimble`

Looking for declarative Nim CLI tool and package management? Pair `vfox-nim` with **[vfox-nimble](https://github.com/elijahr/vfox-nimble)**, a native mise backend plugin:

```bash
# Manage the Nim compiler and toolchain with vfox-nim
mise use vfox:elijahr/vfox-nim@latest

# Install and isolate Nimble CLI tools with vfox-nimble
mise use nimble:c2nim@latest
mise use nimble:nimlsp@latest
```

---

## Continuous Integration: Using mise & vfox (GitHub Actions & Forgejo)

Both `mise` and `vfox` can be used to set up Nim in CI across Linux, macOS, and Windows runners, including self-hosted Forgejo runners.

### Option 1: Using `mise` (Recommended for CI)

`mise` provides first-class GitHub and Forgejo Actions support with built-in tool caching across Linux, macOS, and Windows.

#### In GitHub Actions (Linux, macOS, Windows)

##### Pattern A: With `mise.toml` in your repository (Recommended)

In your repository `mise.toml`:

```toml
[tools]
"vfox:elijahr/vfox-nim" = "2.2.8"
```

In `.github/workflows/ci.yml`:

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

      - name: Set up mise & tools
        uses: jdx/mise-action@v4
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          cache: true

      - name: Verify & Test
        shell: bash
        run: |
          nim --version
          nimble test
```

##### Pattern B: Inline plugin declaration (Without repository `mise.toml`)

```yaml
      - name: Set up mise & Nim
        uses: jdx/mise-action@v4
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          cache: true
          plugins: |
            nim https://github.com/elijahr/vfox-nim.git
          tool_versions: |
            nim 2.2.8
```

#### In Forgejo Actions (`act_runner` / Docker)

```yaml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: docker
    container:
      image: catthehacker/ubuntu:act-24.04
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies & mise
        run: |
          apt-get update && apt-get install -y --no-install-recommends \
            build-essential ca-certificates curl git xz-utils
          curl -fsSL https://mise.run | sh
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"
          echo "$HOME/.local/share/mise/shims" >> "$GITHUB_PATH"

      - name: Install Nim via vfox-nim & run tests
        run: |
          export MISE_GITHUB_ATTESTATIONS=0
          mise plugin install nim https://github.com/elijahr/vfox-nim.git
          mise use -g nim@2.2.8
          nim --version
          nimble test
```

### Option 2: Using standalone `vfox`

#### In GitHub Actions (Linux, macOS, Windows)

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

      - name: Install vfox (Linux & macOS)
        if: runner.os != 'Windows'
        run: |
          if [ "$RUNNER_OS" = "Linux" ]; then
            echo "deb [trusted=yes] https://apt.fury.io/versionfox/ /" | sudo tee /etc/apt/sources.list.d/versionfox.list
            sudo apt-get update && sudo apt-get install -y vfox
          else
            brew tap version-fox/tap && brew install vfox
          fi

      - name: Install vfox (Windows)
        if: runner.os == 'Windows'
        uses: MinoruSekine/setup-scoop@v5.0.1
        with:
          apps: vfox

      - name: Install Nim via vfox
        shell: bash
        run: |
          vfox add --source https://github.com/elijahr/vfox-nim/archive/refs/heads/main.zip --alias nim
          vfox install nim@2.2.8
          vfox use -g nim@2.2.8
          eval "$(vfox activate bash)"
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
        run: |
          eval "$(vfox activate bash)"
          nimble test
```

#### In Forgejo Actions (`act_runner` / Docker)

```yaml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: docker
    container:
      image: catthehacker/ubuntu:act-24.04
    steps:
      - uses: actions/checkout@v4

      - name: Install vfox & Nim
        run: |
          apt-get update && apt-get install -y --no-install-recommends \
            build-essential ca-certificates curl git xz-utils
          echo "deb [trusted=yes] https://apt.fury.io/versionfox/ /" > /etc/apt/sources.list.d/versionfox.list
          apt-get update && apt-get install -y vfox
          vfox add --source https://github.com/elijahr/vfox-nim/archive/refs/heads/main.zip --alias nim
          vfox install nim@2.2.8
          vfox use -g nim@2.2.8
          eval "$(vfox activate bash)"
          nim --version
          nimble --version
          nimble test
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
