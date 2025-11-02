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

function M.normalize_arch(arch)
    arch = arch:lower()
    if arch == "x86_64" or arch == "amd64" then
        return "x86_64"
    elseif arch == "i386" or arch == "i686" or arch == "x86" then
        return "i686"
    elseif arch == "aarch64" then
        return "aarch64"
    elseif arch == "armv7" or arch == "armv7l" then
        return "armv7"
    elseif arch == "arm64" then
        return "arm64" -- macOS specific
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

-- Platform detection
function M.is_windows()
    local handle = io.popen("uname 2>/dev/null || echo Windows")
    local result = handle:read("*a")
    handle:close()
    return result:lower():match("windows") ~= nil or result:lower():match("mingw") ~= nil
end

function M.is_macos()
    local handle = io.popen("uname 2>/dev/null")
    local result = handle:read("*a")
    handle:close()
    return result:lower():match("darwin") ~= nil
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

-- Check if URL exists (HEAD request)
function M.url_exists(url)
    local http = require("http")
    local resp, err = http.head({ url = url, headers = M.get_github_headers() })
    if err ~= nil then
        return false
    end
    return resp.status_code == 200 or resp.status_code == 302
end

-- Adjust date by offset days
function M.adjust_date(date_str, offset)
    -- date_str format: "YYYY-MM-DD"
    local cmd
    if M.is_macos() then
        -- macOS date syntax
        local offset_arg = offset >= 0 and ("+" .. offset .. "d") or (offset .. "d")
        cmd = string.format('date -j -v%s -f "%%Y-%%m-%%d" "%s" "+%%Y-%%m-%%d" 2>/dev/null', offset_arg, date_str)
    else
        -- Linux date syntax
        cmd = string.format('date -d "%s %d days" "+%%Y-%%m-%%d" 2>/dev/null', date_str, offset)
    end

    local handle = io.popen(cmd)
    local result = handle:read("*a"):gsub("%s+$", "")
    handle:close()

    return result
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
    local cmd = "git ls-remote --tags https://github.com/nim-lang/Nim.git refs/tags/" .. tag .. "^{} 2>/dev/null"
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

return M
