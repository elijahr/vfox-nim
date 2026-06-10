> **DEPRECATED — historical Part-2 (vfox-nimble backend) plan, not the current roadmap.**
> The vfox-nimble package backend is explicitly OUT OF SCOPE (see the 2026-06-09
> release-ready design). Retained for historical reference only.

# vfox-nim and vfox-nimble Implementation Plan

**Date**: 2025-11-01
**Author**: Based on production asdf-nim analysis
**Goal**: Create working vfox-nim (tool plugin) and vfox-nimble (backend plugin) with Windows support

---

## Executive Summary

### Why These Plugins Exist

**vfox-nim**:

- Tool plugin to manage Nim compiler versions
- **Primary goal**: Add Windows support (asdf doesn't work on Windows, so asdf-nim explicitly removed Windows support)
- Ports production-proven logic from asdf-nim (67+ tests, battle-tested)
- Supports Linux, macOS, and **Windows** via mise

**vfox-nimble**:

- Backend plugin to manage nimble packages (like vfox-npm manages npm packages)
- Uses `nimble:package@version` format
- Simpler implementation - delegates to nimble CLI
- Provides isolated package installations

### Current State

**vfox-nim**: Template-based, non-functional

- Location: `/Users/elijahrutschman/Development/vfox-nim`
- Status: Placeholder URLs, wrong GitHub API endpoints
- Needs: Complete rewrite of hooks based on asdf-nim logic

**vfox-nimble**: Template-based, non-functional

- Location: `/Users/elijahrutschman/Development/vfox-nimble`
- Status: All hooks are commented examples
- Needs: Research nimble CLI capabilities, then implement 3 simple hooks

### Reference Codebases

**Primary source of truth**:

- `/Users/elijahrutschman/Development/asdf-nim` - Production-ready, 67+ tests
  - Key file: `lib/utils.bash` (1024 lines of proven logic)

**Secondary reference** (Lua syntax only):

- `/Users/elijahrutschman/Development/mise-vfox-nim` - Non-functional, confused implementation
  - Only use for Lua syntax examples, NOT logic

**Backend plugin reference**:

- `/tmp/vfox-npm-reference` - Working backend plugin example

---

## Part 1: vfox-nim Tool Plugin

### Implementation Priority: HIGH (vfox-nimble requires Nim to work)

---

## 1.1: Understanding Nim Binary Distribution

### Official Binaries (nim-lang.org/download/)

**Linux** (tar.xz format):

```
x86_64: https://nim-lang.org/download/nim-{VERSION}-linux_x64.tar.xz
i686:   https://nim-lang.org/download/nim-{VERSION}-linux_x32.tar.xz
```

**Windows** (zip format):

```
x86_64: https://nim-lang.org/download/nim-{VERSION}_x64.zip
i686:   https://nim-lang.org/download/nim-{VERSION}_x32.zip
```

**macOS**: ❌ NO official binaries (use nightly fallback)

**Source**:

```
https://nim-lang.org/download/nim-{VERSION}.tar.xz
```

**CRITICAL**: Notice the URL pattern differences:

- Linux: `nim-VERSION-linux_x64` (dash before platform)
- Windows: `nim-VERSION_x64` (underscore, no "windows" in filename)

### Nightly Binaries (github.com/nim-lang/nightlies/releases)

All platforms available in nightlies:

**Linux** (tar.xz):

- `linux_x64.tar.xz`
- `linux_x32.tar.xz`
- `linux_arm64.tar.xz`
- `linux_armv7l.tar.xz`

**macOS** (tar.xz):

- `macosx_x64.tar.xz`
- `macosx_arm64.tar.xz`

**Windows** (zip):

- `windows_x64.zip`
- `windows_x32.zip`

**Source**:

- `source.tar.xz`

**Nightly release tags**:

- Latest: `latest-devel`, `latest-version-2-2`, `latest-version-2-0`
- Dated: `2025-10-31-version-2-2-{COMMIT_HASH}`

---

## 1.2: The 4-Level Fallback Strategy (from asdf-nim)

This is the **core logic** that makes asdf-nim production-ready. Port this exactly.

### Reference: asdf-nim/lib/utils.bash:729-740

```bash
asdf_nim_download_urls() {
  # 1. Official binaries (Linux x86_64/i686, Windows x86_64/i686)
  asdf_nim_official_archive_url

  # 2. Exact nightly match for stable versions (ALL platforms)
  #    This is the "magic" that gives macOS/ARM users stable versions
  if [ "${ASDF_INSTALL_TYPE}" = "version" ] && [[ ${ASDF_INSTALL_VERSION} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    asdf_nim_find_exact_nightly_url "$ASDF_INSTALL_VERSION"
  fi

  # 3. Generic nightly binaries (ref: versions only - devel, version-2-2, etc.)
  asdf_nim_nightly_url

  # 4. Fall back to building from source
  asdf_nim_source_url
}
```

### Fallback Flow by Platform (for version 2.2.0)

| Platform    | Step 1: Official | Step 2: Exact Nightly | Step 3: Generic | Step 4: Source |
| ----------- | ---------------- | --------------------- | --------------- | -------------- |
| Linux x64   | ✅ FAST (~30s)   | Skip                  | Skip            | Skip           |
| Linux x32   | ✅ FAST (~30s)   | Skip                  | Skip            | Skip           |
| Windows x64 | ✅ FAST (~30s)   | Skip                  | Skip            | Skip           |
| Windows x32 | ✅ FAST (~30s)   | Skip                  | Skip            | Skip           |
| macOS x64   | ❌ No official   | ✅ FAST (~60s)        | Skip            | Skip           |
| macOS ARM64 | ❌ No official   | ✅ FAST (~60s)        | Skip            | Skip           |
| Linux ARM64 | ❌ No official   | ✅ FAST (~60s)        | Skip            | Skip           |
| Linux ARMv7 | ❌ No official   | ✅ FAST (~60s)        | Skip            | Skip           |

### For ref: versions (ref:devel, ref:version-2-2)

All platforms skip to Step 3: Generic nightly (~60s)

---

## 1.3: File-by-File Implementation Guide

### File: `hooks/available.lua`

**Current issue**: Points to wrong GitHub repo
**Reference**: asdf-nim/lib/utils.bash:210-217

**Requirements**:

1. List stable versions from GitHub tags (nim-lang/Nim)
1. List nightly versions from GitHub releases (nim-lang/nightlies)
1. Support both version formats:
   - Stable: `2.2.0`, `1.6.20` (from tags)
   - Nightly: `ref:devel`, `ref:version-2-2`, `ref:version-2-0` (from nightlies)

**Implementation**:

```lua
function PLUGIN:Available(ctx)
    local http = require("http")
    local json = require("json")
    local versions = {}

    -- 1. Get stable versions from nim-lang/Nim tags
    local tags_url = "https://api.github.com/repos/nim-lang/Nim/tags?per_page=100"
    local resp = http.get({
        url = tags_url,
        headers = get_github_headers() -- Include GITHUB_TOKEN if available
    })

    if resp.status_code == 200 then
        local tags = json.decode(resp.body)
        for _, tag in ipairs(tags) do
            local version = tag.name:gsub("^v", "") -- Remove 'v' prefix
            table.insert(versions, {version = version})
        end
    end

    -- 2. Get nightly versions from nim-lang/nightlies releases
    --    Only get "latest-*" tags
    local nightlies_url = "https://api.github.com/repos/nim-lang/nightlies/releases?per_page=100"
    local resp2 = http.get({
        url = nightlies_url,
        headers = get_github_headers()
    })

    if resp2.status_code == 200 then
        local releases = json.decode(resp2.body)
        for _, release in ipairs(releases) do
            if release.tag_name:match("^latest%-") then
                -- Extract branch name: "latest-devel" -> "ref:devel"
                local branch = release.tag_name:gsub("^latest%-", "")
                table.insert(versions, {version = "ref:" .. branch})
            end
        end
    end

    return versions
end

function get_github_headers()
    local token = os.getenv("GITHUB_TOKEN") or os.getenv("GITHUB_API_TOKEN")
    if token then
        return {["Authorization"] = "token " .. token}
    end
    return {}
end
```

**Testing**:

```bash
mise ls-remote nim
# Should show:
# 2.2.6
# 2.2.4
# ...
# ref:devel
# ref:version-2-2
# ref:version-2-0
```

---

### File: `hooks/pre_install.lua`

**Current issue**: Placeholder URLs only
**Reference**: asdf-nim/lib/utils.bash:392-740

**Requirements**:

1. Implement 4-level fallback URL generation
1. Return download URL, sha256 (optional), note (optional)
1. Handle platform detection correctly
1. Support GitHub token for API requests

**Implementation** (complex - this is the core logic):

```lua
function PLUGIN:PreInstall(ctx)
    local version = ctx.version
    local platform = require("platform")
    local os_name = normalize_os(platform.os)
    local arch = normalize_arch(platform.arch)

    -- Determine if this is a stable version or ref
    local is_stable = version:match("^%d+%.%d+%.%d+$") ~= nil
    local is_ref = version:match("^ref:") ~= nil

    if is_ref then
        version = version:gsub("^ref:", "") -- Remove "ref:" prefix
    end

    -- Try URLs in order (4-level fallback)
    local urls = {}

    -- Level 1: Official binaries
    local official_url = get_official_url(version, os_name, arch)
    if official_url then
        table.insert(urls, official_url)
    end

    -- Level 2: Exact nightly match (for stable versions only)
    if is_stable then
        local exact_nightly = find_exact_nightly_url(version, os_name, arch)
        if exact_nightly then
            table.insert(urls, exact_nightly)
        end
    end

    -- Level 3: Generic nightly (for ref: versions)
    if is_ref then
        local nightly_url = find_nightly_url(version, os_name, arch)
        if nightly_url then
            table.insert(urls, nightly_url)
        end
    end

    -- Level 4: Source
    if is_stable then
        local source_url = "https://nim-lang.org/download/nim-" .. version .. ".tar.xz"
        table.insert(urls, source_url)
    end

    -- Return first URL (vfox will try in order if first fails)
    if #urls > 0 then
        return {
            version = version,
            url = urls[1], -- vfox tries urls in order internally
            note = "Platform: " .. os_name .. "/" .. arch
        }
    else
        error("No download URL available for version " .. version .. " on " .. os_name .. "/" .. arch)
    end
end

-- Platform normalization (from asdf-nim:219-297)
function normalize_os(os_name)
    os_name = os_name:lower()
    if os_name:match("darwin") then return "macos"
    elseif os_name:match("linux") then return "linux"
    elseif os_name:match("mingw") or os_name:match("win") then return "windows"
    else return os_name end
end

function normalize_arch(arch)
    arch = arch:lower()
    if arch == "x86_64" or arch == "amd64" then return "x86_64"
    elseif arch == "i386" or arch == "i686" or arch == "x86" then return "i686"
    elseif arch == "aarch64" then return "aarch64"
    elseif arch == "armv7" or arch == "armv7l" then return "armv7"
    elseif arch == "arm64" then return "arm64" -- macOS specific
    else return arch end
end

-- Get platform filename for nightlies (from asdf-nim:479-502)
function get_platform_filename(os_name, arch)
    if os_name == "linux" then
        if arch == "x86_64" then return "linux_x64.tar.xz"
        elseif arch == "i686" then return "linux_x32.tar.xz"
        elseif arch == "aarch64" then return "linux_arm64.tar.xz"
        elseif arch == "armv7" then return "linux_armv7l.tar.xz"
        end
    elseif os_name == "macos" then
        if arch == "x86_64" then return "macosx_x64.tar.xz"
        elseif arch == "arm64" then return "macosx_arm64.tar.xz"
        end
    elseif os_name == "windows" then
        if arch == "x86_64" then return "windows_x64.zip"
        elseif arch == "i686" then return "windows_x32.zip"
        end
    end
    return nil
end

-- Get official binary URL (from asdf-nim:394-406)
function get_official_url(version, os_name, arch)
    if os_name == "linux" then
        if arch == "x86_64" then
            return "https://nim-lang.org/download/nim-" .. version .. "-linux_x64.tar.xz"
        elseif arch == "i686" then
            return "https://nim-lang.org/download/nim-" .. version .. "-linux_x32.tar.xz"
        end
    elseif os_name == "windows" then
        if arch == "x86_64" then
            return "https://nim-lang.org/download/nim-" .. version .. "_x64.zip"
        elseif arch == "i686" then
            return "https://nim-lang.org/download/nim-" .. version .. "_x32.zip"
        end
    end
    -- macOS has no official binaries
    return nil
end

-- Find exact nightly matching stable version (from asdf-nim:639-711)
-- This is the most complex function
function find_exact_nightly_url(version, os_name, arch)
    local platform_filename = get_platform_filename(os_name, arch)
    if not platform_filename then
        return nil
    end

    -- Get commit hash and date for this version
    local commit_hash, commit_date = get_version_commit_info(version)
    if not commit_hash or not commit_date then
        return nil
    end

    -- Calculate branch name: "2.2.0" -> "version-2-2"
    local branch = version_to_branch(version)

    -- Try dates with offsets: +1, 0, +2, -1, -2
    -- (Testing shows nightly builds are usually published day after commit)
    local offsets = {1, 0, 2, -1, -2}

    for _, offset in ipairs(offsets) do
        local check_date = adjust_date(commit_date, offset)

        -- Construct potential nightly tag
        local nightly_tag = check_date .. "-" .. branch .. "-" .. commit_hash

        -- Construct URL
        local url = "https://github.com/nim-lang/nightlies/releases/download/"
                    .. nightly_tag .. "/nim-" .. version .. "-" .. platform_filename

        -- Check if URL exists (HEAD request)
        if url_exists(url) then
            return url
        end
    end

    return nil
end

-- Get commit hash and date for version tag (from asdf-nim:578-637)
function get_version_commit_info(version)
    local cache_dir = os.getenv("HOME") .. "/.cache/vfox-nim"
    local cache_file = cache_dir .. "/version-commits.txt"

    -- Create cache dir
    os.execute("mkdir -p " .. cache_dir)

    -- Check cache first
    local cached = read_cache(cache_file, version)
    if cached then
        return cached.hash, cached.date
    end

    -- Fetch from git
    local tag = "v" .. version
    local cmd = "git ls-remote --tags https://github.com/nim-lang/Nim.git refs/tags/" .. tag .. "^{}"
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()

    if result == "" then
        return nil, nil
    end

    local commit_hash = result:match("^(%S+)")

    -- Get commit date
    local date_cmd = string.format([[
        cd /tmp &&
        rm -rf nim-temp-$$ &&
        git init nim-temp-$$ &&
        cd nim-temp-$$ &&
        git remote add origin https://github.com/nim-lang/Nim.git &&
        git fetch --depth 1 origin %s 2>/dev/null &&
        git show -s --format=%%ci %s 2>/dev/null | cut -d' ' -f1
    ]], commit_hash, commit_hash)

    local date_handle = io.popen(date_cmd)
    local commit_date = date_handle:read("*a"):gsub("%s+$", "")
    date_handle:close()

    if commit_date ~= "" then
        -- Cache it
        write_cache(cache_file, version, commit_hash, commit_date)
        return commit_hash, commit_date
    end

    return nil, nil
end

-- Convert version to branch: "2.2.0" -> "version-2-2"
function version_to_branch(version)
    local major, minor = version:match("^(%d+)%.(%d+)")
    return "version-" .. major .. "-" .. minor
end

-- Adjust date by offset days
function adjust_date(date_str, offset)
    -- date_str format: "YYYY-MM-DD"
    -- Use date command to adjust
    local cmd
    if is_macos() then
        -- macOS date syntax
        local offset_arg = offset >= 0 and ("+" .. offset .. "d") or (offset .. "d")
        cmd = string.format('date -j -v%s -f "%%Y-%%m-%%d" "%s" "+%%Y-%%m-%%d"', offset_arg, date_str)
    else
        -- Linux date syntax
        cmd = string.format('date -d "%s %d days" "+%%Y-%%m-%%d"', date_str, offset)
    end

    local handle = io.popen(cmd)
    local result = handle:read("*a"):gsub("%s+$", "")
    handle:close()

    return result
end

function is_macos()
    local os_type = io.popen("uname"):read("*a"):lower()
    return os_type:match("darwin") ~= nil
end

-- Check if URL exists (HEAD request)
function url_exists(url)
    local http = require("http")
    local resp = http.head({url = url, headers = get_github_headers()})
    return resp.status_code == 200 or resp.status_code == 302
end

-- Find generic nightly URL (from asdf-nim:410-423, 507-564)
function find_nightly_url(branch, os_name, arch)
    local platform_filename = get_platform_filename(os_name, arch)
    if not platform_filename then
        return nil
    end

    local desired_tag = "latest-" .. branch

    -- Fetch nightlies releases
    local http = require("http")
    local json = require("json")

    -- Try up to 4 pages
    for page = 1, 4 do
        local url = "https://api.github.com/repos/nim-lang/nightlies/releases?per_page=100&page=" .. page
        local resp = http.get({url = url, headers = get_github_headers()})

        if resp.status_code ~= 200 then
            break
        end

        local releases = json.decode(resp.body)
        if #releases == 0 then
            break
        end

        -- Find matching release
        for _, release in ipairs(releases) do
            if release.tag_name == desired_tag then
                -- Find asset with our platform filename
                for _, asset in ipairs(release.assets or {}) do
                    if asset.name == platform_filename then
                        return asset.browser_download_url
                    end
                end
            end
        end
    end

    return nil
end

-- Cache helpers
function read_cache(cache_file, version)
    local file = io.open(cache_file, "r")
    if not file then return nil end

    for line in file:lines() do
        local v, hash, date = line:match("^(%S+)%s+(%S+)%s+(%S+)")
        if v == version then
            file:close()
            return {hash = hash, date = date}
        end
    end

    file:close()
    return nil
end

function write_cache(cache_file, version, hash, date)
    local file = io.open(cache_file, "a")
    if file then
        file:write(version .. " " .. hash .. " " .. date .. "\n")
        file:close()
    end
end

function get_github_headers()
    local token = os.getenv("GITHUB_TOKEN") or os.getenv("GITHUB_API_TOKEN")
    if token then
        return {["Authorization"] = "token " .. token}
    end
    return {}
end
```

**Testing**:

```bash
mise install nim@2.2.0        # Should use official binary (Windows/Linux)
mise install nim@ref:devel    # Should use latest nightly
mise install nim@1.6.20       # Should use official binary or exact nightly
```

---

### File: `hooks/post_install.lua`

**Current issue**: Assumes single binary, Nim releases are archives
**Reference**: asdf-nim/lib/utils.bash:809-818, 914-1002

**Requirements**:

1. Extract archives (.tar.xz for Linux/macOS, .zip for Windows)
1. Handle nested directories (archives contain `nim-VERSION/` subdirectory)
1. Build from source if needed (detect build.sh, build_all.sh, etc.)
1. Verify installation (`nim --version`)

**Implementation**:

```lua
function PLUGIN:PostInstall(ctx)
    local install_path = ctx.install_path
    local file = require("file")
    local cmd = require("cmd")

    -- Determine if this is a binary release or source
    local has_build_script = file.exists(install_path .. "/build.sh") or
                             file.exists(install_path .. "/build_all.sh") or
                             file.exists(install_path .. "/build.bat") or
                             file.exists(install_path .. "/build_all.bat")

    if has_build_script then
        -- Source build
        build_from_source(install_path)
    else
        -- Binary release - already extracted by vfox
        -- But we may need to run finish.exe on Windows
        if is_windows() and file.exists(install_path .. "/finish.exe") then
            cmd.exec("cmd", {"/c", install_path .. "\\finish.exe"}, {cwd = install_path})
        end
    end

    -- Verify installation
    local nim_binary = is_windows() and "nim.exe" or "nim"
    local nim_path = install_path .. "/bin/" .. nim_binary

    if not file.exists(nim_path) then
        error("Nim binary not found at " .. nim_path)
    end

    -- Test version
    local version_output = cmd.exec(nim_path, {"--version"})
    if not version_output:match("Nim Compiler") then
        error("Nim installation verification failed")
    end

    return {}
end

function build_from_source(install_path)
    local file = require("file")
    local cmd = require("cmd")
    local platform = require("platform")

    -- Check for existing nim binary
    local nim_exists = file.exists(install_path .. "/bin/nim") or
                       file.exists(install_path .. "/bin/nim.exe")

    if not nim_exists then
        -- Bootstrap nim
        if is_windows() then
            if file.exists(install_path .. "/build_all.bat") then
                cmd.exec("cmd", {"/c", "build_all.bat"}, {cwd = install_path})
            elseif file.exists(install_path .. "/build.bat") then
                cmd.exec("cmd", {"/c", "build.bat"}, {cwd = install_path})
            else
                error("No build script found for Windows")
            end
        else
            if file.exists(install_path .. "/build_all.sh") then
                cmd.exec("sh", {"build_all.sh"}, {cwd = install_path})
            elseif file.exists(install_path .. "/build.sh") then
                cmd.exec("sh", {"build.sh"}, {cwd = install_path})
            else
                error("No build script found")
            end
        end
    end

    -- Build koch if needed
    if not file.exists(install_path .. "/koch") and not file.exists(install_path .. "/koch.exe") then
        local nim = install_path .. "/bin/nim"
        if is_windows() then nim = nim .. ".exe" end
        cmd.exec(nim, {"c", "--skipParentCfg:on", "-d:release", "koch"}, {cwd = install_path})
    end

    -- Build nim with koch if needed
    local koch = install_path .. "/koch"
    if is_windows() then koch = koch .. ".exe" end

    if file.exists(koch) then
        cmd.exec(koch, {"boot", "-d:release"}, {cwd = install_path})

        -- Build tools
        if not file.exists(install_path .. "/bin/nimgrep") and
           not file.exists(install_path .. "/bin/nimgrep.exe") then
            cmd.exec(koch, {"tools", "-d:release"}, {cwd = install_path})
        end

        -- Build nimble if not present
        if not file.exists(install_path .. "/bin/nimble") and
           not file.exists(install_path .. "/bin/nimble.exe") then
            cmd.exec(koch, {"nimble", "-d:release"}, {cwd = install_path})
        end
    end
end

function is_windows()
    local platform = require("platform")
    return platform.os:lower():match("win") ~= nil
end
```

**Testing**:

```bash
mise install nim@2.2.0
nim --version  # Should show "Nim Compiler Version 2.2.0"
```

---

### File: `hooks/env_keys.lua`

**Current status**: Basic PATH only
**Reference**: asdf-nim/bin/exec-env

**Requirements**:

1. Set PATH to include Nim's bin directory
1. Set NIMBLE_DIR with 3-level priority:
   - Priority 1: Respect existing NIMBLE_DIR environment variable
   - Priority 2: Check for ./nimbledeps in current working directory
   - Priority 3: Fall back to {install_path}/nimble

**Implementation**:

```lua
function PLUGIN:EnvKeys(ctx)
    local install_path = ctx.install_path
    local file = require("file")
    local env_vars = {}

    -- Add bin to PATH
    table.insert(env_vars, {
        key = "PATH",
        value = file.join_path(install_path, "bin")
    })

    -- Set NIMBLE_DIR with priority system
    local nimble_dir = get_nimble_dir(install_path)
    if nimble_dir then
        table.insert(env_vars, {
            key = "NIMBLE_DIR",
            value = nimble_dir
        })
    end

    return env_vars
end

function get_nimble_dir(install_path)
    local file = require("file")

    -- Priority 1: Existing NIMBLE_DIR
    local existing_nimble_dir = os.getenv("NIMBLE_DIR")
    if existing_nimble_dir and existing_nimble_dir ~= "" then
        return nil -- Don't override existing
    end

    -- Priority 2: Project-local nimbledeps
    local cwd = os.getenv("PWD") or "."
    local nimbledeps = file.join_path(cwd, "nimbledeps")
    if file.exists(nimbledeps) then
        return nil -- Let Nim detect it naturally
    end

    -- Priority 3: Per-version nimble directory
    return file.join_path(install_path, "nimble")
end
```

**Testing**:

```bash
mise use nim@2.2.0
echo $NIMBLE_DIR  # Should show ~/.local/share/mise/installs/nim/2.2.0/nimble
cd project-with-nimbledeps
echo $NIMBLE_DIR  # Should be empty (or existing value)
```

---

### File: `lib/nim_utils.lua` (NEW - shared utilities)

Create this file to share common functions:

```lua
-- lib/nim_utils.lua
-- Shared utilities for vfox-nim plugin

local M = {}

-- Platform normalization
function M.normalize_os(os_name)
    os_name = os_name:lower()
    if os_name:match("darwin") then return "macos"
    elseif os_name:match("linux") then return "linux"
    elseif os_name:match("mingw") or os_name:match("win") then return "windows"
    else return os_name end
end

function M.normalize_arch(arch)
    arch = arch:lower()
    if arch == "x86_64" or arch == "amd64" then return "x86_64"
    elseif arch == "i386" or arch == "i686" or arch == "x86" then return "i686"
    elseif arch == "aarch64" then return "aarch64"
    elseif arch == "armv7" or arch == "armv7l" then return "armv7"
    elseif arch == "arm64" then return "arm64"
    else return arch end
end

-- Get platform filename for nightlies
function M.get_platform_filename(os_name, arch)
    if os_name == "linux" then
        if arch == "x86_64" then return "linux_x64.tar.xz"
        elseif arch == "i686" then return "linux_x32.tar.xz"
        elseif arch == "aarch64" then return "linux_arm64.tar.xz"
        elseif arch == "armv7" then return "linux_armv7l.tar.xz"
        end
    elseif os_name == "macos" then
        if arch == "x86_64" then return "macosx_x64.tar.xz"
        elseif arch == "arm64" then return "macosx_arm64.tar.xz"
        end
    elseif os_name == "windows" then
        if arch == "x86_64" then return "windows_x64.zip"
        elseif arch == "i686" then return "windows_x32.zip"
        end
    end
    return nil
end

-- GitHub API helpers
function M.get_github_headers()
    local token = os.getenv("GITHUB_TOKEN") or os.getenv("GITHUB_API_TOKEN")
    if token then
        return {["Authorization"] = "token " .. token}
    end
    return {}
end

-- Version parsing
function M.version_to_branch(version)
    local major, minor = version:match("^(%d+)%.(%d+)")
    return "version-" .. major .. "-" .. minor
end

function M.is_stable_version(version)
    return version:match("^%d+%.%d+%.%d+$") ~= nil
end

function M.is_ref_version(version)
    return version:match("^ref:") ~= nil
end

-- Platform detection
function M.is_windows()
    local platform = require("platform")
    return platform.os:lower():match("win") ~= nil
end

function M.is_macos()
    local platform = require("platform")
    return platform.os:lower():match("darwin") ~= nil
end

return M
```

---

## 1.4: Testing Strategy

### Unit Tests (using Busted framework)

Create `spec/` directory with tests:

**spec/nim_utils_spec.lua**:

```lua
describe("nim_utils", function()
    local utils = require("lib.nim_utils")

    describe("normalize_os", function()
        it("normalizes Darwin to macos", function()
            assert.equals("macos", utils.normalize_os("Darwin"))
        end)

        it("normalizes MINGW to windows", function()
            assert.equals("windows", utils.normalize_os("MINGW64_NT"))
        end)
    end)

    describe("normalize_arch", function()
        it("normalizes amd64 to x86_64", function()
            assert.equals("x86_64", utils.normalize_arch("amd64"))
        end)

        it("normalizes i386 to i686", function()
            assert.equals("i686", utils.normalize_arch("i386"))
        end)
    end)

    describe("get_platform_filename", function()
        it("returns correct Linux x64 filename", function()
            assert.equals("linux_x64.tar.xz", utils.get_platform_filename("linux", "x86_64"))
        end)

        it("returns correct Windows x64 filename", function()
            assert.equals("windows_x64.zip", utils.get_platform_filename("windows", "x86_64"))
        end)

        it("returns correct macOS ARM64 filename", function()
            assert.equals("macosx_arm64.tar.xz", utils.get_platform_filename("macos", "arm64"))
        end)
    end)

    describe("version_to_branch", function()
        it("converts 2.2.0 to version-2-2", function()
            assert.equals("version-2-2", utils.version_to_branch("2.2.0"))
        end)

        it("converts 1.6.20 to version-1-6", function()
            assert.equals("version-1-6", utils.version_to_branch("1.6.20"))
        end)
    end)
end)
```

**spec/available_spec.lua** - Test version listing
**spec/pre_install_spec.lua** - Test URL generation
**spec/post_install_spec.lua** - Test installation
**spec/env_keys_spec.lua** - Test environment setup

### Integration Tests

Update `mise-tasks/test`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Link plugin locally
mise plugin link --force nim "$PWD"

# Clear cache
mise cache clear

echo "Testing stable version installation (2.2.0)..."
mise install nim@2.2.0

echo "Verifying nim binary..."
nim_path="$(mise where nim@2.2.0)/bin/nim"
if [ ! -f "$nim_path" ]; then
    echo "Error: nim binary not found at $nim_path"
    exit 1
fi

echo "Checking nim version..."
version_output="$("$nim_path" --version)"
if ! echo "$version_output" | grep -q "Nim Compiler Version 2.2.0"; then
    echo "Error: Unexpected version output: $version_output"
    exit 1
fi

echo "Testing nightly version (ref:devel)..."
mise install nim@ref:devel

echo "Verifying nightly nim binary..."
nim_devel_path="$(mise where nim@ref:devel)/bin/nim"
if [ ! -f "$nim_devel_path" ]; then
    echo "Error: nim devel binary not found at $nim_devel_path"
    exit 1
fi

echo "Testing NIMBLE_DIR..."
eval "$(mise env -s bash)"
if [ -z "${NIMBLE_DIR:-}" ]; then
    echo "Error: NIMBLE_DIR not set"
    exit 1
fi

echo "All tests passed!"
```

### CI Configuration

Update `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Install mise
        uses: jdx/mise-action@v2

      - name: Run tests
        run: mise run test
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## Part 2: vfox-nimble Backend Plugin

### Implementation Priority: MEDIUM (after vfox-nim works)

---

## 2.1: Research Phase (MUST DO FIRST)

Before implementing, verify these assumptions about nimble CLI:

```bash
# Install Nim first
mise use nim@2.2.0

# Test 1: Can we list package versions?
nimble search parsetoml
nimble search parsetoml --ver
# Expected: List of available versions

# Test 2: Does NIMBLE_DIR work for installation?
mkdir -p /tmp/test-nimble
NIMBLE_DIR=/tmp/test-nimble nimble install parsetoml@0.7.0 --accept
ls /tmp/test-nimble
# Expected: Files installed in /tmp/test-nimble

# Test 3: Where are binaries placed?
ls /tmp/test-nimble/bin
# Expected: parsetoml binary exists

# Test 4: Does nimble have JSON output?
nimble search --help | grep -i json
# Expected: Check if --json flag exists

# Test 5: How to query specific package versions?
nimble search parsetoml
# Document the output format
```

**Document findings** before proceeding with implementation.

---

## 2.2: Implementation (After Research)

### File: `hooks/backend_list_versions.lua`

**Reference**: /tmp/vfox-npm-reference/hooks/backend_list_versions.lua

**Implementation** (adjust based on research findings):

```lua
function PLUGIN:BackendListVersions(ctx)
    local cmd = require("cmd")
    local tool = ctx.tool

    -- Try to get versions from nimble
    -- This implementation depends on research findings

    -- Option A: If nimble supports JSON output
    local result = cmd.exec("nimble search " .. tool .. " --json")
    local json = require("json")
    local data = json.decode(result)
    -- Parse versions from JSON

    -- Option B: If nimble only has text output
    local result = cmd.exec("nimble search " .. tool)
    local versions = parse_nimble_text_output(result)

    return {versions = versions}
end

function parse_nimble_text_output(output)
    -- Parse text output to extract versions
    -- Format depends on actual nimble output
    local versions = {}

    -- Example parsing (adjust based on actual format):
    -- Output might be: "parsetoml 0.7.0 - Parse TOML files"
    for line in output:gmatch("[^\r\n]+") do
        local version = line:match("(%d+%.%d+%.%d+)")
        if version then
            table.insert(versions, version)
        end
    end

    return versions
end
```

---

### File: `hooks/backend_install.lua`

**Reference**: /tmp/vfox-npm-reference/hooks/backend_install.lua

**Implementation**:

```lua
function PLUGIN:BackendInstall(ctx)
    local cmd = require("cmd")
    local tool = ctx.tool
    local version = ctx.version
    local install_path = ctx.install_path

    -- Set NIMBLE_DIR to isolate this installation
    local env = {
        NIMBLE_DIR = install_path
    }

    -- Install the package using nimble
    local nimble_cmd = "nimble install " .. tool .. "@" .. version .. " --accept"

    cmd.exec(nimble_cmd, {
        cwd = install_path,
        env = env
    })

    return {}
end
```

---

### File: `hooks/backend_exec_env.lua`

**Reference**: /tmp/vfox-npm-reference/hooks/backend_exec_env.lua

**Implementation**:

```lua
function PLUGIN:BackendExecEnv(ctx)
    local file = require("file")
    local install_path = ctx.install_path

    return {
        env_vars = {
            {key = "NIMBLE_DIR", value = install_path},
            {key = "PATH", value = file.join_path(install_path, "bin")}
        }
    }
end
```

---

### File: `metadata.lua`

**Current status**: Already customized
**Action**: Verify correctness

```lua
PLUGIN = {}

PLUGIN.name = "nimble"
PLUGIN.version = "1.0.0"
PLUGIN.homepage = "https://github.com/elijahr/vfox-nimble"
PLUGIN.license = "MIT"
PLUGIN.description = "vfox backend plugin for nimble package manager"

PLUGIN.notes = {
    "Requires Nim to be installed (use vfox-nim)",
    "Manages nimble packages using nimble:package@version format"
}
```

---

### Testing

Update `mise-tasks/test`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Ensure Nim is installed first
if ! command -v nim &> /dev/null; then
    echo "Error: Nim must be installed first (use vfox-nim)"
    exit 1
fi

# Link plugin locally
mise plugin link --force nimble "$PWD"

# Clear cache
mise cache clear

echo "Testing package version listing..."
mise ls-remote nimble:parsetoml | head -5

echo "Testing package installation (parsetoml@0.7.0)..."
mise install nimble:parsetoml@0.7.0

echo "Verifying package binary..."
parsetoml_path="$(mise where nimble:parsetoml@0.7.0)/bin/parsetoml"
if [ ! -f "$parsetoml_path" ]; then
    echo "Error: parsetoml binary not found at $parsetoml_path"
    exit 1
fi

echo "Testing execution..."
mise exec nimble:parsetoml@0.7.0 -- parsetoml --version

echo "Testing multiple packages..."
mise install nimble:regex@0.25.0

echo "Verifying isolation..."
# Both packages should exist independently
if [ ! -f "$(mise where nimble:parsetoml@0.7.0)/bin/parsetoml" ]; then
    echo "Error: parsetoml isolation broken"
    exit 1
fi

if [ ! -f "$(mise where nimble:regex@0.25.0)/bin/regex" ]; then
    echo "Error: regex isolation broken"
    exit 1
fi

echo "All tests passed!"
```

---

## Implementation Phases

### Phase 1: vfox-nim Core (Week 1-2)

**Day 1-2**: Platform detection and URL generation

- Implement `lib/nim_utils.lua`
- Implement `hooks/available.lua`
- Implement `hooks/pre_install.lua` (official + nightly URLs)
- Write unit tests
- Test: `mise ls-remote nim`

**Day 3-4**: Exact nightly matching

- Implement `find_exact_nightly_url()` logic
- Implement commit hash fetching
- Implement date adjustment
- Test on macOS (no official binaries)

**Day 5**: Archive extraction and post-install

- Implement `hooks/post_install.lua`
- Handle .tar.xz and .zip extraction
- Test: `mise install nim@2.2.0`

**Day 6**: Source builds

- Implement build from source logic
- Test on exotic platform or old version
- Test: `mise install nim@1.0.0` (old version)

**Day 7**: Environment and NIMBLE_DIR

- Implement `hooks/env_keys.lua`
- Implement 3-level NIMBLE_DIR priority
- Test: `mise use nim@2.2.0`, check env vars

**Day 8-9**: Testing

- Write comprehensive unit tests
- Write integration tests
- Test on Linux, macOS, Windows (if available)
- Fix bugs

**Day 10**: Documentation and CI

- Update README.md
- Configure GitHub Actions
- Test CI pipeline

### Phase 2: vfox-nimble (Week 3)

**Day 1-2**: Research

- Test nimble CLI capabilities
- Document findings
- Design implementation based on findings

**Day 3-4**: Implementation

- Implement `backend_list_versions.lua`
- Implement `backend_install.lua`
- Implement `backend_exec_env.lua`
- Update metadata.lua

**Day 5**: Testing

- Write integration tests
- Test with multiple packages
- Test isolation

**Day 6**: Documentation and CI

- Update README.md
- Configure CI
- Publish

---

## Success Criteria

### vfox-nim:

- ✅ `mise install nim@2.2.0` works on Linux, macOS, Windows
- ✅ Windows uses official binary (< 30s install)
- ✅ macOS uses exact nightly match (< 60s install)
- ✅ `mise install nim@ref:devel` works on all platforms
- ✅ NIMBLE_DIR set correctly with 3-level priority
- ✅ CI tests pass on all 3 platforms
- ✅ 50+ unit tests, 100% pass rate
- ✅ Integration tests pass

### vfox-nimble:

- ✅ `mise ls-remote nimble:parsetoml` lists versions
- ✅ `mise install nimble:parsetoml@0.7.0` works
- ✅ Binary accessible via `mise exec`
- ✅ Multiple packages can coexist
- ✅ NIMBLE_DIR isolated per package
- ✅ Works on Windows

---

## Quick Reference: Key URLs

**Official binaries**:

```
Linux x64:    https://nim-lang.org/download/nim-{VERSION}-linux_x64.tar.xz
Linux x32:    https://nim-lang.org/download/nim-{VERSION}-linux_x32.tar.xz
Windows x64:  https://nim-lang.org/download/nim-{VERSION}_x64.zip
Windows x32:  https://nim-lang.org/download/nim-{VERSION}_x32.zip
Source:       https://nim-lang.org/download/nim-{VERSION}.tar.xz
```

**Nightly binaries**:

```
Latest:       https://github.com/nim-lang/nightlies/releases/latest/download-{BRANCH}/{PLATFORM}.tar.xz
Dated:        https://github.com/nim-lang/nightlies/releases/download/{DATE}-{BRANCH}-{HASH}/nim-{VERSION}-{PLATFORM}.tar.xz
```

**GitHub APIs**:

```
Nim tags:     https://api.github.com/repos/nim-lang/Nim/tags
Nightlies:    https://api.github.com/repos/nim-lang/nightlies/releases
```

---

## Environment Variables

**User configuration**:

- `GITHUB_TOKEN` - Increases GitHub API rate limit (60 → 5000 req/hour)
- `NIMBLE_DIR` - Custom nimble package directory (respected by vfox-nim)

**vfox-nim specific** (optional):

- `VFOX_NIM_NO_NIGHTLY_FALLBACK` - Set to "1" to disable nightly fallback, force source builds

---

## Common Issues and Solutions

### Issue: GitHub API rate limit exceeded

**Solution**: Set GITHUB_TOKEN environment variable

```bash
export GITHUB_TOKEN=ghp_your_token_here
```

### Issue: Windows build fails (source)

**Solution**: Install MinGW or Visual Studio

```bash
# Install MinGW via chocolatey
choco install mingw

# Or install Visual Studio Build Tools
```

### Issue: macOS M1 build fails

**Solution**: Ensure Xcode command line tools installed

```bash
xcode-select --install
```

### Issue: nimble packages not found in PATH

**Solution**: Use `mise exec` or activate the environment

```bash
# Option 1: Use exec
mise exec nimble:parsetoml@0.7.0 -- parsetoml file.toml

# Option 2: Activate
eval "$(mise activate bash)"
parsetoml file.toml
```

---

## Repository Locations

- **vfox-nim**: `/Users/elijahrutschman/Development/vfox-nim`
- **vfox-nimble**: `/Users/elijahrutschman/Development/vfox-nimble`
- **asdf-nim** (reference): `/Users/elijahrutschman/Development/asdf-nim`
- **mise-vfox-nim** (Lua syntax reference): `/Users/elijahrutschman/Development/mise-vfox-nim`
- **vfox-npm** (backend reference): `/tmp/vfox-npm-reference`

---

## Final Notes

1. **Windows is the priority** - That's why vfox-nim exists
1. **asdf-nim is the source of truth** - Port logic exactly, don't "improve" it
1. **Test on Windows** - CI must include Windows runners
1. **Document Windows-specific issues** - MinGW requirements, path separators, etc.
1. **vfox-nimble depends on vfox-nim** - Implement vfox-nim first, test thoroughly
1. **Research before implementing vfox-nimble** - Don't assume, verify nimble CLI behavior

Good luck! 🚀
