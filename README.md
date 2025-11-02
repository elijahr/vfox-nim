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

- Configurable installation method (auto/binary/source)
- Includes Nim compiler, Nimble package manager, and tools

## Quick Start

### With mise

```bash
# Install the plugin
mise plugins install nim

# Install latest Nim
mise install nim@latest

# Or install a specific version
mise install nim@2.0.0

# Set as global default
mise use -g nim@latest
```

### With vfox

```bash
# Install the plugin
vfox add nim

# Install latest Nim
vfox install nim@latest

# Set as global default
vfox use -g nim@latest
```

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

**Testing your configuration:**

```bash
# See what environment variables are set
mise env | grep VFOX_NIM

# Install a version to test the configuration
mise install nim@2.0.0

# Check the installation note
mise ls nim
```

## Development

```bash
# Link plugin for development
mise plugin link --force nim .

# Run tests
mise run test

# Run linting
mise run lint
```

## License

MIT
