-- Test helpers and mocks for mise globals

local M = {}

-- Add hooks directory to package path so tests can require lib modules
package.path = package.path .. ";hooks/?.lua;hooks/?/init.lua"

-- Mock PLUGIN global (used by backend and vfox hooks)
_G.PLUGIN = {}

-- Mock RUNTIME global
_G.RUNTIME = {
    osType = "Linux",
    archType = "x86_64",
}

-- Mock ctx global
_G.ctx = {
    version = "2.2.4",
    install_path = "/test/install/path",
    path = "/test/install/path",
    sdkInfo = {
        nim = {
            name = "nim",
            version = "2.2.4",
            path = "/test/install/path",
        },
    },
}

-- Mock http module (as both global and package)
local http_mock = {
    get = function(opts)
        -- Default mock response
        return {
            status_code = 200,
            body = "[]",
        }, nil
    end,
    head = function(opts)
        return {
            status_code = 200,
        }, nil
    end,
    download_file = function(url, dest)
        -- Mock download - do nothing
    end,
}

_G.http = http_mock
package.preload["http"] = function()
    return http_mock
end

-- Mock json module (as both global and package)
local json_mock = {
    decode = function(str)
        -- Simple JSON decode mock
        if str == "[]" then
            return {}
        end
        -- For more complex mocks, tests can override this
        return {}
    end,
    encode = function(obj)
        return "{}"
    end,
}

_G.json = json_mock
package.preload["json"] = function()
    return json_mock
end

-- Mock file module
_G.file = {
    join_path = function(...)
        local parts = { ... }
        return table.concat(parts, "/")
    end,
    exists = function(path)
        return false
    end,
    is_dir = function(path)
        return false
    end,
    create_dir = function(path)
        -- Mock - do nothing
    end,
    remove = function(path)
        -- Mock - do nothing
    end,
    remove_dir = function(path)
        -- Mock - do nothing
    end,
    list_dir = function(path)
        return {}
    end,
    rename = function(src, dst)
        -- Mock - do nothing
    end,
}

-- Mock cmd module
_G.cmd = {
    exec = function(args, opts)
        return {
            exit_code = 0,
            stdout = "",
            stderr = "",
        }
    end,
}

-- Mock env module
_G.env = {
    prepend_path = function(name, value)
        -- Mock - do nothing
    end,
    set = function(name, value)
        -- Mock - do nothing
    end,
    get = function(name)
        return nil
    end,
}

-- Mock strings module
_G.strings = {
    split = function(str, delimiter)
        local result = {}
        for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
            table.insert(result, match)
        end
        return result
    end,
}

-- Mock archiver module
_G.archiver = {
    decompress = function(archive, dest)
        -- Mock - do nothing
    end,
}

-- Helper to set custom mocks for specific tests
function M.mock_http_get(url_pattern, response)
    local original_get = _G.http.get
    _G.http.get = function(url, opts)
        if url:match(url_pattern) then
            return response
        end
        return original_get(url, opts)
    end
end

function M.mock_json_decode(response)
    _G.json.decode = function(str)
        return response
    end
end

function M.reset_mocks()
    -- Reset all mocks to defaults
    _G.PLUGIN = {}

    _G.RUNTIME = {
        osType = "Linux",
        archType = "x86_64",
    }

    _G.ctx = {
        version = "2.2.4",
        install_path = "/test/install/path",
    }
end

return M
