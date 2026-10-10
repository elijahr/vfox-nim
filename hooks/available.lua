-- hooks/available.lua
-- Returns a list of available versions for Nim
-- Documentation: https://mise.jdx.dev/tool-plugin-development.html#available-hook

function PLUGIN:Available(ctx)
    local http = require("http")
    local json = require("json")
    local versions = {}

    -- Fallback list of stable releases if GitHub API is unreachable or rate-limited
    local fallback_versions = {
        "2.2.10",
        "2.2.8",
        "2.2.6",
        "2.2.4",
        "2.2.2",
        "2.2.0",
        "2.0.8",
        "2.0.6",
        "2.0.4",
        "2.0.2",
        "2.0.0",
        "1.6.20",
        "1.6.18",
        "1.6.16",
        "1.6.14",
        "1.6.12",
        "1.6.10",
        "1.6.8",
        "1.6.6",
        "1.6.4",
        "1.6.2",
        "1.6.0",
    }

    -- Helper to get GitHub headers with token if available
    local function get_github_headers()
        local token = os.getenv("GITHUB_TOKEN") or os.getenv("GITHUB_API_TOKEN")
        if token and token ~= "" then
            if not token:match("^%a+%s+") then
                token = "token " .. token
            end
            return { ["Authorization"] = token }
        end
        return {}
    end

    -- 1. Get stable versions from nim-lang/Nim tags
    local tags_url = "https://api.github.com/repos/nim-lang/Nim/tags?per_page=100"
    local resp, err = http.get({
        url = tags_url,
        headers = get_github_headers(),
    })

    if err == nil and resp and resp.status_code == 200 and resp.body then
        local ok, tags = pcall(json.decode, resp.body)
        if ok and type(tags) == "table" then
            for _, tag in ipairs(tags) do
                if tag.name then
                    local version = tag.name:gsub("^v", "") -- Remove 'v' prefix
                    -- Only include versions that match X.Y.Z pattern
                    if version:match("^%d+%.%d+%.%d+$") then
                        table.insert(versions, { version = version })
                    end
                end
            end
        end
    end

    -- If API failed or was rate-limited, fall back to known stable releases
    if #versions == 0 then
        for _, v in ipairs(fallback_versions) do
            table.insert(versions, { version = v })
        end
    end

    -- 2. Expose Nimony releases from nim-lang/nimony-website
    -- We expose floating nimony-latest, unique milestone versions (e.g. nimony-0.6.3),
    -- and up to 5 recent specific nightly builds (e.g. nimony-0.6.3-b3806c1ce)
    local nimony_url = "https://api.github.com/repos/nim-lang/nimony-website/releases?per_page=20"
    local n_resp, n_err = http.get({
        url = nimony_url,
        headers = get_github_headers(),
    })

    local nimony_versions = {
        { version = "nimony-latest" },
    }

    if n_err == nil and n_resp and n_resp.status_code == 200 and n_resp.body then
        local ok, releases = pcall(json.decode, n_resp.body)
        if ok and type(releases) == "table" then
            local seen_milestones = {}
            local milestones = {}
            local recent_nightlies = {}

            for _, release in ipairs(releases) do
                if release.tag_name then
                    -- Extract milestone version, e.g. 0.6.3 from nightly-0.6.3-b3806c1ce
                    local v = release.tag_name:match("^nightly%-(%d+%.%d+%.%d+)")
                    if v and not seen_milestones[v] then
                        seen_milestones[v] = true
                        table.insert(milestones, "nimony-" .. v)
                    end

                    -- Collect up to 5 most recent specific nightly builds
                    if #recent_nightlies < 5 then
                        local tag_suffix = release.tag_name:match("^nightly%-(.+)$")
                        if tag_suffix then
                            table.insert(recent_nightlies, "nimony-" .. tag_suffix)
                        end
                    end
                end
            end

            for _, m in ipairs(milestones) do
                table.insert(nimony_versions, { version = m })
            end
            for _, rn in ipairs(recent_nightlies) do
                table.insert(nimony_versions, { version = rn })
            end
        end
    end

    if #nimony_versions == 1 then
        table.insert(nimony_versions, { version = "nimony-0.6.3" })
    end

    -- Append nimony versions at the end of the list so stable Nim releases remain primary
    for _, nv in ipairs(nimony_versions) do
        table.insert(versions, nv)
    end

    -- Note: We don't list nightly "ref:" versions here because:
    -- 1. mise filters out non-standard version formats from ls-remote
    -- 2. Users can still use them directly: `mise install nim@ref:devel`
    -- 3. The pre_install hook will handle ref: versions correctly

    return versions
end
