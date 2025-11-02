-- hooks/pre_install.lua
-- Returns download information for a specific Nim version
-- Documentation: https://mise.jdx.dev/tool-plugin-development.html#preinstall-hook

function PLUGIN:PreInstall(ctx)
    local version = ctx.version
    local utils = require("lib.nim_utils")

    -- Get platform information
    local os_name = utils.normalize_os(RUNTIME.osType)
    local arch = utils.normalize_arch(RUNTIME.archType)

    -- Determine if this is a stable version or ref
    local is_stable = utils.is_stable_version(version)
    local is_ref = utils.is_ref_version(version)

    -- Extract ref prefix if present
    local actual_version = version
    if is_ref then
        actual_version = version:gsub("^ref:", "")
    end

    -- Try URLs in order (4-level fallback strategy)
    -- Level 1: Official binaries (Linux x86_64/i686, Windows x86_64/i686 only)
    if is_stable then
        local official_url = utils.get_official_url(actual_version, os_name, arch)
        if official_url then
            -- Verify URL exists before returning it
            if utils.url_exists(official_url) then
                return {
                    version = actual_version,
                    url = official_url,
                    note = "Official binary for " .. os_name .. "/" .. arch,
                }
            end
        end
    end

    -- Level 2: Exact nightly match (for stable versions only, all platforms)
    -- This is the "magic" that gives macOS/ARM users stable versions
    if is_stable then
        local exact_nightly = utils.find_exact_nightly_url(actual_version, os_name, arch)
        if exact_nightly then
            return {
                version = actual_version,
                url = exact_nightly,
                note = "Nightly build matching " .. actual_version .. " for " .. os_name .. "/" .. arch,
            }
        end
    end

    -- Level 3: Generic nightly binaries (for ref: versions only)
    if is_ref then
        local nightly_url = utils.find_nightly_url(actual_version, os_name, arch)
        if nightly_url then
            return {
                version = actual_version,
                url = nightly_url,
                note = "Latest nightly build for " .. actual_version .. " on " .. os_name .. "/" .. arch,
            }
        end
    end

    -- Level 4: Fall back to building from source (stable versions only)
    if is_stable then
        local source_url = "https://nim-lang.org/download/nim-" .. actual_version .. ".tar.xz"
        return {
            version = actual_version,
            url = source_url,
            note = "Building from source (no pre-built binary available for " .. os_name .. "/" .. arch .. ")",
        }
    end

    -- If we get here, we couldn't find any download option
    error(
        "No download URL available for version "
            .. version
            .. " on "
            .. os_name
            .. "/"
            .. arch
            .. ". This may indicate an unsupported platform or invalid version."
    )
end
