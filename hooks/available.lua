-- hooks/available.lua
-- Returns a list of available versions for Nim
-- Documentation: https://mise.jdx.dev/tool-plugin-development.html#available-hook

function PLUGIN:Available(ctx)
    local http = require("http")
    local json = require("json")
    local versions = {}

    -- Helper to get GitHub headers with token if available
    local function get_github_headers()
        local token = os.getenv("GITHUB_TOKEN") or os.getenv("GITHUB_API_TOKEN")
        if token then
            return { ["Authorization"] = "token " .. token }
        end
        return {}
    end

    -- 1. Get stable versions from nim-lang/Nim tags
    local tags_url = "https://api.github.com/repos/nim-lang/Nim/tags?per_page=100"
    local resp, err = http.get({
        url = tags_url,
        headers = get_github_headers(),
    })

    if err == nil and resp.status_code == 200 then
        local tags = json.decode(resp.body)
        for _, tag in ipairs(tags) do
            local version = tag.name:gsub("^v", "") -- Remove 'v' prefix
            -- Only include versions that match X.Y.Z pattern
            if version:match("^%d+%.%d+%.%d+$") then
                table.insert(versions, { version = version })
            end
        end
    end

    -- Note: We don't list nightly "ref:" versions here because:
    -- 1. mise filters out non-standard version formats from ls-remote
    -- 2. Users can still use them directly: `mise install nim@ref:devel`
    -- 3. The pre_install hook will handle ref: versions correctly

    return versions
end
