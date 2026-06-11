# Changelog

All notable changes to vfox-nim are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Renamed the install-method environment variable from `VFOX_NIM_INSTALL_METHOD`
  to `NIM_INSTALL_METHOD`. Neither mise nor vfox defines a plugin-prefixed env-var
  convention, and the plugin is installed under the name `nim`, so the `VFOX_`
  prefix was misleading (it also runs under mise). The `mise.toml` `install_method`
  tool option is unchanged and remains the primary way to configure mise.

## [0.1.1]

_Not yet released — the `v0.1.1` tag and GitHub Release are created by the **Release** workflow (manually dispatched from `main` after this commit lands)._

### Added

- Multi-arch end-to-end CI (`arch-e2e.yml`): binary-only Nim installs on emulated
  Linux `aarch64` and `armv7` (vfox under `uraimo/run-on-arch-action`) and on macOS
  x64 (`macos-15-intel` via mise). Runs on push-to-main, manual dispatch, and a
  weekly cron (kept off the per-PR path).
- README: status badges, an install demo placeholder plus a `console` transcript,
  a scannable feature list, a "Installing versions" section (latest / specific /
  partial-series / `ref:devel` / branches / commits / `.nim-version` / `GITHUB_TOKEN`),
  and a "GitHub Actions" usage guide including the Windows Nim DLL setup.
- Community infrastructure: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`,
  bug-report and feature-request issue forms, and a pull-request template.

### Changed

- README platform table: the Windows rows no longer claim source-build support
  (the plugin installs prebuilt binaries on Windows and does not build from source
  there); the Source Build column is marked unsupported for the Windows rows.
- README now presents vfox-nim explicitly as an independent third-party plugin
  installed from this repository under a local plugin name, rather than as a
  registry-provided `nim`.

### Fixed

- `normalize_arch` now also handles the 32-bit values vfox/mise actually emit: Go's
  `GOARCH` `386` (vfox, 32-bit x86) maps to `i686`, and `arm` (both tools, 32-bit ARM)
  maps to `armv7`. Previously only `i386`/`i686`/`x86` and `armv7`/`armv7l` were
  matched — values neither tool emits for those targets — so Windows/Linux x32 (under
  vfox) and Linux ARMv7 (under both) failed to resolve a binary. Unit tests now assert
  the real emitted values through to the resolved asset URLs.
- `normalize_arch` is now OS-aware: it returns `aarch64` for both
  `aarch64` and `arm64` input on Linux (matching Nim's nightly +
  source tarball naming) and keeps `arm64` on macOS. The prior
  bare-arch normalization returned `arm64` unconditionally, so on
  Linux/arm64 hosts `get_platform_filename` rejected the result and
  `PreInstall` fell through to a source build — which currently
  fails because the Nim 2.x `csources_v2` HEAD is broken. Net effect
  pre-fix: `v0.1.0` could not install Nim on Linux/arm64 at all.
- Same fix benefits mise-on-Linux/arm64, since mise's RUNTIME shim
  passes Go's `runtime.GOARCH == "arm64"` verbatim too.
- Added install_method spec coverage for the Linux/arm64 path
  (which was missing — only macOS/arm64 was exercised previously)
  and the macOS/arm64 path, and tightened the smoke spec's
  architecture-normalization assertions to cover both spellings.

## [0.1.0]

_Released via the **Release** workflow (manually dispatched from `main`)._

### Changed

- No longer set `NIMBLE_DIR` to a per-version `<install>/nimble` path (inherited
  from `asdf-nim`). It is now left unset so nim uses the shared `~/.nimble`
  (matching `choosenim`), preventing package loss on version reinstall and keeping
  nimble packages out of the managed install directory. A user-set `NIMBLE_DIR` and
  project-local `nimbledeps` auto-detection are both still honored.

### Added

- Initial release: 4-level Nim installer (official binaries → exact nightly →
  generic nightly → source) with Linux, macOS, and Windows support.
- Tier-II install-logic unit test driving the real date-offset + nightly-tag logic
  via a GitHub commits-API fixture.

### Fixed

- CI Lua toolchain root-fix: provision a dlopen-capable Lua 5.1-ABI interpreter +
  luarocks + busted via a `setup-lua` composite action (PUC Lua 5.1 via hererocks on
  Linux/macOS — LuaJIT is intentionally avoided there due to its 65536-constant limit
  on the luarocks manifest; MSYS2-native PUC Lua 5.1 (`mingw-w64-x86_64-lua51`) on
  Windows), replacing the static-no-dlopen interpreter and the broken `withLuaPath`
  luarocks step across all three test jobs.
- `adjust_date` now uses pure-integer civil-day arithmetic (no `date` shell-out),
  fixing the Windows date-offset failure and removing timezone/DST dependence.
- Hardened `is_windows`/`is_macos` to derive the OS from `RUNTIME.osType`.
- Integration spec uses `os.tmpname()` for its archive path (collision/`act` safety).
- Windows: `vfox install nim` failed in `post_install.lua` two ways — exec'd command
  paths mixed `/` and `\` separators (cmd.exe rejected them), and the install was
  verified by a shell-quoted `nim --version` that cmd.exe (vfox) and POSIX sh (mise)
  can't both parse. Fixed by composing native (backslash) paths on Windows and
  verifying the binary by file existence; the version check still runs on Unix.
- Windows: cmd.exe leading-quote mangling in `post_install.lua` — when an exec'd
  command started with a quoted path (e.g. `"…\nim.exe" --version`), cmd.exe's
  quote-stripping broke the command under vfox. Fixed by wrapping the whole command
  in an extra outer quote pair on Windows only (Unix form unchanged).
- Windows: use `2>nul` (not `2>/dev/null`) for stderr suppression on cmd.exe-reachable
  command sites, so they don't print a stray "system cannot find" message.
- Documented the durable local dev loop (LuaJIT + luarocks tree + busted/luacheck),
  the `mise trust` requirement, and how to make `luacheck` available for pre-commit.

### Notes

- Windows: the source-build install method is not supported (the prebuilt binary
  install is used instead); `auto` correctly selects the binary on Windows. The
  explicit `VFOX_NIM_INSTALL_METHOD=source` integration test is skipped on Windows and
  still runs on macOS/Linux.
- Windows CI: the full 3-OS matrix — unit tests plus the mise and vfox integration
  suites (a real `nim` install end-to-end) — passes on `ubuntu-latest`, `macos-latest`,
  and `windows-latest`, and the Windows legs are blocking (not `continue-on-error`).

[Unreleased]: https://github.com/elijahr/vfox-nim/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/elijahr/vfox-nim/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/elijahr/vfox-nim/releases/tag/v0.1.0
