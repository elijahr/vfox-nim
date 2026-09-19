-- hooks/pre_install.lua
-- Returns download information for a specific Nim version
-- Documentation: https://mise.jdx.dev/tool-plugin-development.html#preinstall-hook

local utils = require("lib.nim_utils")

function PLUGIN:PreInstall(ctx)
    local version = ctx.version

    -- Get install method: check ctx.options first (native mise tool option),
    -- then environment variable (set by MiseEnv hook or user).
    -- Valid values: "auto" (default), "binary", "source"
    local install_method = "auto"
    local ok, val = pcall(function()
        return ctx.options.install_method
    end)
    if ok and val and val ~= "" then
        install_method = val
    elseif os.getenv("NIM_INSTALL_METHOD") then
        install_method = os.getenv("NIM_INSTALL_METHOD")
    end

    -- Get platform information. normalize_arch needs os_name to disambiguate
    -- the aarch64/arm64 spelling (Linux uses "aarch64"; macOS uses "arm64"),
    -- so normalize_os must run first.
    local os_name = utils.normalize_os(RUNTIME.osType)
    local arch = utils.normalize_arch(RUNTIME.archType, os_name)

    -- Determine if this is a stable version or ref
    local is_stable = utils.is_stable_version(version)
    local is_ref = utils.is_ref_version(version)

    -- Extract ref prefix if present
    local actual_version = version
    if is_ref then
        actual_version = version:gsub("^ref:", "")
    end

    -- Handle dry-run diagnostic mode (Issue #6)
    local function finish(resolved)
        local dry_run = os.getenv("NIM_DRY_RUN")
        if dry_run == "1" or dry_run == "true" or dry_run == "yes" then
            print("[vfox-nim dry-run]")
            print("  Requested Version : " .. version)
            print("  Resolved Version  : " .. resolved.version)
            print("  Platform          : " .. os_name .. "/" .. arch)
            print("  Install Method    : " .. install_method)
            print("  Resolution Note   : " .. (resolved.note or "none"))
            print("  Download URL      : " .. resolved.url)
            error("[vfox-nim] Dry-run completed successfully (no files downloaded).")
        end
        return resolved
    end

    -- If install_method is "source", skip binary lookups and build from source
    if install_method == "source" then
        if is_stable then
            -- Stable version: use official source tarball
            local source_url = "https://nim-lang.org/download/nim-" .. actual_version .. ".tar.xz"
            return finish({
                version = actual_version,
                url = source_url,
                note = "Building from source (user preference: install_method='source')",
            })
        else
            -- ref: version: download tarball from GitHub
            local source_url = "https://github.com/nim-lang/Nim/archive/" .. actual_version .. ".tar.gz"
            return finish({
                version = actual_version,
                url = source_url,
                note = "Building from source for ref:"
                    .. actual_version
                    .. " (user preference: install_method='source')",
            })
        end
    end

    -- Try URLs in order (3-level fallback strategy for binaries)
    -- Level 1: Official binaries (Linux x86_64/i686, Windows x86_64/i686 only)
    if is_stable then
        local official_url = utils.get_official_url(actual_version, os_name, arch)
        if official_url then
            -- Verify URL exists before returning it
            if utils.url_exists(official_url) then
                return finish({
                    version = actual_version,
                    url = official_url,
                    note = "Official binary for " .. os_name .. "/" .. arch,
                })
            end
        end
    end

    -- Level 2: Exact nightly match (for stable versions only, all platforms)
    -- This is the "magic" that gives macOS/ARM users stable versions
    if is_stable then
        local exact_nightly = utils.find_exact_nightly_url(actual_version, os_name, arch)
        if exact_nightly then
            return finish({
                version = actual_version,
                url = exact_nightly,
                note = "Nightly build matching " .. actual_version .. " for " .. os_name .. "/" .. arch,
            })
        end
    end

    -- Level 3: Generic nightly binaries (for ref: versions only)
    if is_ref then
        local nightly_url = utils.find_nightly_url(actual_version, os_name, arch)
        if nightly_url then
            return finish({
                version = actual_version,
                url = nightly_url,
                note = "Latest nightly build for " .. actual_version .. " on " .. os_name .. "/" .. arch,
            })
        end
    end

    -- No binary available - check install_method to decide what to do
    if install_method == "binary" then
        -- User wants binary-only, fail with clear error
        error(
            "No pre-built binary available for version "
                .. version
                .. " on "
                .. os_name
                .. "/"
                .. arch
                .. ". User preference install_method='binary' prevents building from source."
        )
    end

    -- install_method == "auto": Fall back to building from source
    if is_stable then
        local source_url = "https://nim-lang.org/download/nim-" .. actual_version .. ".tar.xz"
        return finish({
            version = actual_version,
            url = source_url,
            note = "Building from source (no pre-built binary available for " .. os_name .. "/" .. arch .. ")",
        })
    else
        -- ref: version with auto mode - download GitHub tarball
        local source_url = "https://github.com/nim-lang/Nim/archive/" .. actual_version .. ".tar.gz"
        return finish({
            version = actual_version,
            url = source_url,
            note = "Building from source for ref:" .. actual_version .. " (no pre-built binary available)",
        })
    end
end
