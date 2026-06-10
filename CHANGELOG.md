# Changelog

All notable changes to vfox-nim are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

_Not yet released — the `v0.1.0` tag is created by CI on merge to the default branch._

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

[Unreleased]: https://github.com/elijahr/vfox-nim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/elijahr/vfox-nim/releases/tag/v0.1.0
