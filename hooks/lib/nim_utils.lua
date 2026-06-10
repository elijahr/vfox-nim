-- lib/nim_utils.lua
-- Shared utilities for vfox-nim plugin
-- Ported from asdf-nim production logic

local M = {}

-- Platform normalization (from asdf-nim:219-297)
function M.normalize_os(os_name)
    os_name = os_name:lower()
    if os_name:match("darwin") then
        return "macos"
    elseif os_name:match("linux") then
        return "linux"
    elseif os_name:match("mingw") or os_name:match("win") then
        return "windows"
    else
        return os_name
    end
end

-- Normalize arch to the spelling Nim's distribution channels use. The 64-bit
-- ARM spelling is platform-specific: macOS calls it `arm64` (and Nim's macOS
-- nightly + tarball URLs match that), while Linux nightly + source tarball URLs
-- spell it `aarch64`. vfox/mise pass Go's `runtime.GOARCH` verbatim, which is
-- `arm64` on Linux/ARM64 hosts too, so the `aarch64`/`arm64` branch below has
-- to pivot on `os_name` to pick the right downstream spelling.
function M.normalize_arch(arch, os_name)
    arch = arch:lower()
    if arch == "x86_64" or arch == "amd64" then
        return "x86_64"
    elseif arch == "i386" or arch == "i686" or arch == "x86" then
        return "i686"
    elseif arch == "aarch64" or arch == "arm64" then
        if os_name == "macos" or os_name == "darwin" then
            return "arm64"
        end
        return "aarch64"
    elseif arch == "armv7" or arch == "armv7l" then
        return "armv7"
    else
        return arch
    end
end

-- Get platform filename for nightlies (from asdf-nim:479-502)
function M.get_platform_filename(os_name, arch)
    if os_name == "linux" then
        if arch == "x86_64" then
            return "linux_x64.tar.xz"
        elseif arch == "i686" then
            return "linux_x32.tar.xz"
        elseif arch == "aarch64" then
            return "linux_arm64.tar.xz"
        elseif arch == "armv7" then
            return "linux_armv7l.tar.xz"
        end
    elseif os_name == "macos" then
        if arch == "x86_64" then
            return "macosx_x64.tar.xz"
        elseif arch == "arm64" then
            return "macosx_arm64.tar.xz"
        end
    elseif os_name == "windows" then
        if arch == "x86_64" then
            return "windows_x64.zip"
        elseif arch == "i686" then
            return "windows_x32.zip"
        end
    end
    return nil
end

-- GitHub API helpers
function M.get_github_headers()
    local token = os.getenv("GITHUB_TOKEN") or os.getenv("GITHUB_API_TOKEN")
    if token then
        return { ["Authorization"] = "token " .. token }
    end
    return {}
end

-- Version parsing
function M.version_to_branch(version)
    local major, minor = version:match("^(%d+)%.(%d+)")
    if not major or not minor then
        return nil
    end
    return "version-" .. major .. "-" .. minor
end

function M.is_stable_version(version)
    return version:match("^%d+%.%d+%.%d+$") ~= nil
end

function M.is_ref_version(version)
    return version:match("^ref:") ~= nil
end

-- Platform detection.
-- Authoritative inside a hook: vfox/mise injects RUNTIME.osType. Fall back to the
-- OS env var (Windows_NT on all Windows), then uname, for standalone/test contexts.
function M.is_windows()
    if RUNTIME and RUNTIME.osType then
        return RUNTIME.osType:lower():match("windows") ~= nil
    end
    if os.getenv("OS") == "Windows_NT" then
        return true
    end
    -- package.config's first char is the platform path separator: "\\" on Windows,
    -- "/" on Unix. This detects Windows without a uname shell-out and is a no-op on Unix.
    if package and package.config and package.config:sub(1, 1) == "\\" then
        return true
    end
    local handle = io.popen("uname 2>/dev/null")
    if not handle then
        return false
    end
    local result = (handle:read("*a") or ""):lower()
    handle:close()
    return result:match("mingw") ~= nil or result:match("msys") ~= nil or result:match("windows") ~= nil
end

-- OS-aware "discard stderr" redirect for commands run through a shell.
-- `2>/dev/null` is POSIX; under cmd.exe (vfox-on-Windows) the equivalent is `2>nul`,
-- and the POSIX form would leave `/dev/null` as a stray arg and emit
-- "The system cannot find the path specified." Use this only for command strings that
-- can actually run through cmd.exe on Windows; the Unix form is preserved byte-for-byte.
function M.null_redirect()
    if M.is_windows() then
        return "2>nul"
    end
    return "2>/dev/null"
end

function M.is_macos()
    -- Windows is never macOS; short-circuit FIRST, before any RUNTIME or uname
    -- inspection. On Unix is_windows()'s package.config check is "/" so this is a
    -- no-op; on Windows it guarantees is_macos() never shells out to uname.
    if M.is_windows() then
        return false
    end
    if RUNTIME and RUNTIME.osType then
        local t = RUNTIME.osType:lower()
        return t:match("darwin") ~= nil or t:match("macos") ~= nil
    end
    local handle = io.popen("uname 2>/dev/null")
    if not handle then
        return false
    end
    local result = (handle:read("*a") or ""):lower()
    handle:close()
    return result:match("darwin") ~= nil
end

-- Get official binary URL (from asdf-nim:394-406)
function M.get_official_url(version, os_name, arch)
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

-- Check if URL exists (HEAD request).
-- Only api.github.com calls carry the GitHub Authorization header. Release-download
-- URLs (github.com/.../releases/download/...) and nim-lang.org are public and 302-redirect
-- to a presigned asset host that REJECTS a forwarded Authorization header with HTTP 401;
-- attaching the token there makes url_exists wrongly report the asset as missing. The
-- 60/hr unauthenticated rate limit applies to api.github.com, not to asset downloads, so
-- non-api hosts need no auth header at all.
function M.url_exists(url)
    local http = require("http")
    local headers = {}
    if url:match("^https://api%.github%.com") then
        headers = M.get_github_headers()
    end
    local resp, err = http.head({ url = url, headers = headers })
    if err ~= nil or not resp then
        return false
    end
    return resp.status_code == 200 or resp.status_code == 302
end

-- Days since 1970-01-01 for a proleptic-Gregorian civil date (Howard Hinnant's algorithm).
-- Pure integer arithmetic; valid for any Lua 5.1+/LuaJIT/gopher-lua. m in 1..12.
local function days_from_civil(y, m, d)
    y = (m <= 2) and (y - 1) or y
    local era = math.floor((y >= 0 and y or (y - 399)) / 400)
    local yoe = y - era * 400 -- [0, 399]
    local doy = math.floor((153 * ((m > 2) and (m - 3) or (m + 9)) + 2) / 5) + d - 1 -- [0, 365]
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy -- [0, 146096]
    return era * 146097 + doe - 719468
end

-- Inverse: civil date (y, m, d) from a day count since 1970-01-01.
local function civil_from_days(z)
    z = z + 719468
    local era = math.floor((z >= 0 and z or (z - 146096)) / 146097)
    local doe = z - era * 146097 -- [0, 146096]
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365) -- [0, 399]
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100)) -- [0, 365]
    local mp = math.floor((5 * doy + 2) / 153) -- [0, 11]
    local d = doy - math.floor((153 * mp + 2) / 5) + 1 -- [1, 31]
    local m = mp < 10 and (mp + 3) or (mp - 9) -- [1, 12]
    return (m <= 2) and (y + 1) or y, m, d
end

-- Adjust "YYYY-MM-DD" by `offset` days, returns "YYYY-MM-DD".
-- Pure integer arithmetic: timezone-, DST-, and OS-independent. No os.time/os.date/shell-out.
function M.adjust_date(date_str, offset)
    -- Defensive: a nil/non-string date_str would crash the :match below. Return the
    -- same "" the function already yields for malformed input (consistent with the
    -- install_logic_spec expectation that garbage input yields "").
    if type(date_str) ~= "string" then
        return ""
    end
    local y, m, d = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then
        return ""
    end
    local days = days_from_civil(tonumber(y), tonumber(m), tonumber(d)) + offset
    local ny, nm, nd = civil_from_days(days)
    return string.format("%04d-%02d-%02d", ny, nm, nd)
end

-- Cache helpers
function M.read_cache(cache_file, version)
    local file = io.open(cache_file, "r")
    if not file then
        return nil
    end

    for line in file:lines() do
        local v, hash, date = line:match("^(%S+)%s+(%S+)%s+(%S+)")
        if v == version then
            file:close()
            return { hash = hash, date = date }
        end
    end

    file:close()
    return nil
end

function M.write_cache(cache_file, version, hash, date)
    local file = io.open(cache_file, "a")
    if file then
        file:write(version .. " " .. hash .. " " .. date .. "\n")
        file:close()
    end
end

-- Get commit hash and date for version tag (from asdf-nim:578-637)
function M.get_version_commit_info(version)
    local cache_dir = os.getenv("HOME") .. "/.cache/vfox-nim"
    local cache_file = cache_dir .. "/version-commits.txt"

    -- Create cache dir
    os.execute("mkdir -p " .. cache_dir)

    -- Check cache first
    local cached = M.read_cache(cache_file, version)
    if cached then
        return cached.hash, cached.date
    end

    -- Fetch from git
    local tag = "v" .. version
    -- OS-aware stderr discard: this io.popen runs through cmd.exe on Windows during version
    -- resolution, where `2>/dev/null` would misfire; M.null_redirect() yields `2>nul` there.
    local cmd = "git ls-remote --tags https://github.com/nim-lang/Nim.git refs/tags/"
        .. tag
        .. "^{} "
        .. M.null_redirect()
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()

    if result == "" then
        return nil, nil
    end

    local commit_hash = result:match("^(%S+)")
    if not commit_hash then
        return nil, nil
    end

    -- Get commit date using GitHub API (more reliable than cloning)
    local http = require("http")
    local json = require("json")
    local api_url = "https://api.github.com/repos/nim-lang/Nim/commits/" .. commit_hash
    local resp, err = http.get({ url = api_url, headers = M.get_github_headers() })

    if err == nil and resp.status_code == 200 then
        local commit_data = json.decode(resp.body)
        if commit_data.commit and commit_data.commit.committer and commit_data.commit.committer.date then
            local commit_date = commit_data.commit.committer.date:match("^(%d%d%d%d%-%d%d%-%d%d)")
            if commit_date then
                -- Cache it
                M.write_cache(cache_file, version, commit_hash, commit_date)
                return commit_hash, commit_date
            end
        end
    end

    return commit_hash, nil
end

-- Find exact nightly matching stable version (from asdf-nim:639-711)
function M.find_exact_nightly_url(version, os_name, arch)
    local platform_filename = M.get_platform_filename(os_name, arch)
    if not platform_filename then
        return nil
    end

    -- Get commit hash and date for this version
    local commit_hash, commit_date = M.get_version_commit_info(version)
    if not commit_hash or not commit_date then
        return nil
    end

    -- Calculate branch name: "2.2.0" -> "version-2-2"
    local branch = M.version_to_branch(version)
    if not branch then
        return nil
    end

    -- Try dates with offsets: +1, 0, +2, -1, -2
    local offsets = { 1, 0, 2, -1, -2 }

    for _, offset in ipairs(offsets) do
        local check_date = M.adjust_date(commit_date, offset)
        if check_date and check_date ~= "" then
            -- Construct potential nightly tag
            local nightly_tag = check_date .. "-" .. branch .. "-" .. commit_hash

            -- Construct URL
            local url = "https://github.com/nim-lang/nightlies/releases/download/"
                .. nightly_tag
                .. "/nim-"
                .. version
                .. "-"
                .. platform_filename

            -- Check if URL exists (HEAD request)
            if M.url_exists(url) then
                return url
            end
        end
    end

    return nil
end

-- Find generic nightly URL (from asdf-nim:410-423, 507-564)
function M.find_nightly_url(branch, os_name, arch)
    local platform_filename = M.get_platform_filename(os_name, arch)
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
        local resp, err = http.get({ url = url, headers = M.get_github_headers() })

        if err ~= nil or resp.status_code ~= 200 then
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

function M.dump(o)
    if type(o) == "table" then
        local s = "{ "
        for k, v in pairs(o) do
            if type(k) ~= "number" then
                k = '"' .. k .. '"'
            end
            s = s .. "[" .. k .. "] = " .. M.dump(v) .. ","
        end
        return s .. "} "
    else
        return tostring(o)
    end
end

return M
