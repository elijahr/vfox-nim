# vfox-nim

Nim version manager plugin for [mise](https://mise.jdx.dev/) and [vfox](https://vfox.dev/). Installs Nim and the Nimony toolchain on Linux, macOS, and Windows.

[![CI](https://github.com/elijahr/vfox-nim/actions/workflows/test.yml/badge.svg)](https://github.com/elijahr/vfox-nim/actions/workflows/test.yml)
[![Latest release](https://img.shields.io/github/v/release/elijahr/vfox-nim)](https://github.com/elijahr/vfox-nim/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Why use this?

- **Prebuilts across platforms**: Linux (x86_64, arm64), macOS (Apple Silicon, Intel), and Windows (x86_64).
- **Source build fallback**: Automatically compiles Nim from C source bootstrap if a prebuilt binary is not published for your platform or requested version (unlike mise's default `http:nim` backend, which fails when a prebuilt archive is missing).
- **Development & Nimony builds**: Install `ref:devel`, exact Git commits, or Nimony (`nimony`, `nimony-0.6.3`) directly.
- **Compiler module imports**: Configures `path = "$nim"` in `config/nim.cfg` so tools that import `compiler/ast` or `compiler/options` work immediately.

---

## Installation & Local Usage

### With mise

**CLI**:

```bash
# Install and use globally via plugin URL:
mise use -g vfox:elijahr/vfox-nim@latest

# Or register as 'nim' to drop the prefix:
mise plugin install nim https://github.com/elijahr/vfox-nim
mise use -g nim@latest
```

**In `mise.toml`**:

```toml
[tools]
"vfox:elijahr/vfox-nim" = "2.2.10"
# Or if registered via `mise plugin install nim`:
# nim = "2.2.10"
```

**Version Examples**:

```bash
mise install nim@2.2.10                  # Official stable release
mise install nim@ref:devel               # Nightly devel branch
mise install nim@ref:1a2b3c4             # Specific Git commit
mise install nim@nimony                  # Latest Nimony nightly
mise install nim@nimony-0.6.3            # Nimony milestone
mise install nim@nightly-0.6.3-b3806c1ce # Specific Nimony commit build
```

---

### With vfox

**CLI**:

```bash
vfox add --source https://github.com/elijahr/vfox-nim/archive/refs/heads/main.zip --alias nim
vfox install nim@latest
vfox use -g nim@latest
```

**In `.tool-versions`**:

```text
nim 2.2.10
```

---

## GitHub Actions CI Matrix

Use the composite GitHub Action to test across platforms and Nim versions:

```yaml
name: CI
on: [push, pull_request]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        nim: ["2.2.10", "ref:devel", "nimony"]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Set up Nim
        uses: elijahr/vfox-nim@main
        with:
          version: ${{ matrix.nim }}

      - name: Run tests
        shell: bash
        run: |
          nim --version
          nimble test
```

_(If your repository already uses `mise.toml`, you can use `jdx/mise-action@v4` instead)._

---

## Configuration

Set `install_method` to control binary vs source installation:

- `auto` (default): Download prebuilt binary; build from source if unavailable.
- `binary`: Prebuilt binary only. Errors if no binary exists for your platform.
- `source`: Compile from source using bootstrap C sources (Linux and macOS only).

**Via environment variable**:

```bash
export NIM_INSTALL_METHOD="binary"
```

**In `mise.toml`**:

```toml
[env]
_."vfox:elijahr/vfox-nim" = { install_method = "binary" }
```

---

## Companion Tool: `vfox-nimble`

To declare and manage project-local Nimble CLI tools (such as `nimlsp` or `c2nim`) in `mise.toml`, pair this with [vfox-nimble](https://github.com/elijahr/vfox-nimble).

---

## License

This project is licensed under the [MIT License](LICENSE).
