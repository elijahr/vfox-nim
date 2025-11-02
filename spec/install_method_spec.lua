-- Unit tests for install_method behavior in pre_install hook
require("spec.helpers")

describe("pre_install install_method behavior", function()
    before_each(function()
        -- Reset PLUGIN
        _G.PLUGIN = { name = "nim" }

        -- Set up default ctx
        _G.ctx = {
            version = "2.2.4",
        }

        -- Set up RUNTIME
        _G.RUNTIME = {
            osType = "Linux",
            archType = "x86_64",
        }

        -- Mock os.getenv
        _G.os.getenv_orig = _G.os.getenv
        _G.os.getenv = function(name)
            if name == "VFOX_NIM_INSTALL_METHOD" then
                return nil -- Default: no env var set
            end
            if name == "HOME" then
                return "/tmp/test-home"
            end
            return nil
        end

        -- Mock http module
        local http = require("http")
        http.head = function(opts)
            return { status_code = 200 }, nil
        end
        http.get = function(opts)
            return { status_code = 200, body = "[]" }, nil
        end
    end)

    after_each(function()
        if _G.os.getenv_orig then
            _G.os.getenv = _G.os.getenv_orig
        end
    end)

    describe("install_method = 'auto' (default)", function()
        it("tries binaries first for Linux x86_64", function()
            dofile("hooks/pre_install.lua")
            ctx.version = "2.2.4"
            RUNTIME.osType = "Linux"
            RUNTIME.archType = "x86_64"

            local result = PLUGIN:PreInstall(ctx)
            assert.is_table(result)
            assert.is_string(result.url)
            -- Should get official binary for Linux x86_64
            assert.matches("linux_x64", result.url)
        end)

        it("falls back to source when no binary available", function()
            -- Mock http.head to return 404 (no binary)
            local http = require("http")
            http.head = function(opts)
                return { status_code = 404 }, nil
            end
            http.get = function(opts)
                -- Return empty JSON array for nightly builds list
                return { status_code = 200, body = "[]" }, nil
            end
            local json = require("json")
            json.decode = function(str)
                return {} -- Empty list of nightly builds
            end

            dofile("hooks/pre_install.lua")
            ctx.version = "2.2.4"
            RUNTIME.osType = "Darwin"
            RUNTIME.archType = "arm64"

            local result = PLUGIN:PreInstall(ctx)
            assert.is_table(result)
            assert.is_string(result.url)
            -- Should fall back to source
            assert.matches("2%.2%.4.*tar%.xz", result.url)
            assert.matches("nim%-lang%.org", result.url)
        end)
    end)

    describe("install_method = 'source'", function()
        before_each(function()
            _G.os.getenv = function(name)
                if name == "VFOX_NIM_INSTALL_METHOD" then
                    return "source"
                end
                return nil
            end
        end)

        it("always builds from source for stable versions", function()
            dofile("hooks/pre_install.lua")
            ctx.version = "2.2.4"
            RUNTIME.osType = "Linux"
            RUNTIME.archType = "x86_64"

            local result = PLUGIN:PreInstall(ctx)
            assert.is_table(result)
            assert.is_string(result.url)
            -- Should get source tarball
            assert.matches("nim%-2%.2%.4%.tar%.xz", result.url)
            assert.matches("nim%-lang%.org", result.url)
            assert.matches("source", result.note:lower())
        end)

        it("downloads GitHub tarball for ref versions", function()
            dofile("hooks/pre_install.lua")
            ctx.version = "ref:devel"

            local result = PLUGIN:PreInstall(ctx)

            assert.is_not_nil(result)
            assert.equals("devel", result.version)
            assert.matches("github.com/nim%-lang/Nim/archive/devel%.tar%.gz", result.url)
            assert.matches("Building from source for ref:devel", result.note)
        end)
    end)

    describe("install_method = 'binary'", function()
        before_each(function()
            _G.os.getenv = function(name)
                if name == "VFOX_NIM_INSTALL_METHOD" then
                    return "binary"
                end
                if name == "HOME" then
                    return "/tmp/test-home"
                end
                return nil
            end
        end)

        it("uses binaries when available", function()
            dofile("hooks/pre_install.lua")
            ctx.version = "2.2.4"
            RUNTIME.osType = "Linux"
            RUNTIME.archType = "x86_64"

            local result = PLUGIN:PreInstall(ctx)
            assert.is_table(result)
            assert.is_string(result.url)
            -- Should get official binary
            assert.matches("linux_x64", result.url)
        end)

        it("errors when no binary available", function()
            -- Mock http to return 404 (no binaries)
            local http = require("http")
            http.head = function(opts)
                return { status_code = 404 }, nil
            end
            http.get = function(opts)
                -- Return empty JSON array for nightly builds list
                return { status_code = 200, body = "[]" }, nil
            end
            local json = require("json")
            json.decode = function(str)
                return {} -- Empty list of nightly builds
            end

            dofile("hooks/pre_install.lua")
            ctx.version = "2.2.4"
            RUNTIME.osType = "Darwin"
            RUNTIME.archType = "arm64"

            local success, err = pcall(function()
                PLUGIN:PreInstall(ctx)
            end)

            assert.is_false(success)
            assert.matches("No pre%-built binary available", err)
            assert.matches("install_method='binary'", err)
        end)
    end)

    describe("reading VFOX_NIM_INSTALL_METHOD from environment", function()
        it("reads 'auto' from environment", function()
            _G.os.getenv = function(name)
                if name == "VFOX_NIM_INSTALL_METHOD" then
                    return "auto"
                end
                if name == "HOME" then
                    return "/tmp/test-home"
                end
                return nil
            end

            dofile("hooks/pre_install.lua")
            ctx.version = "2.2.4"
            RUNTIME.osType = "Linux"
            RUNTIME.archType = "x86_64"

            local result = PLUGIN:PreInstall(ctx)
            assert.is_table(result)
            -- Should succeed with binary
            assert.matches("linux_x64", result.url)
        end)

        it("reads 'binary' from environment", function()
            _G.os.getenv = function(name)
                if name == "VFOX_NIM_INSTALL_METHOD" then
                    return "binary"
                end
                if name == "HOME" then
                    return "/tmp/test-home"
                end
                return nil
            end

            dofile("hooks/pre_install.lua")
            ctx.version = "2.2.4"
            RUNTIME.osType = "Linux"
            RUNTIME.archType = "x86_64"

            local result = PLUGIN:PreInstall(ctx)
            assert.is_table(result)
            -- Should get binary
            assert.is_string(result.url)
        end)

        it("reads 'source' from environment", function()
            _G.os.getenv = function(name)
                if name == "VFOX_NIM_INSTALL_METHOD" then
                    return "source"
                end
                if name == "HOME" then
                    return "/tmp/test-home"
                end
                return nil
            end

            dofile("hooks/pre_install.lua")
            ctx.version = "2.2.4"

            local result = PLUGIN:PreInstall(ctx)
            assert.is_table(result)
            -- Should get source
            assert.matches("tar%.xz", result.url)
        end)

        it("supports direct environment variable without MiseEnv hook", function()
            -- Simulate setting the env var directly (not through MiseEnv hook)
            _G.os.getenv = function(name)
                if name == "VFOX_NIM_INSTALL_METHOD" then
                    return "binary"
                end
                if name == "HOME" then
                    return "/tmp/test-home"
                end
                return nil
            end

            dofile("hooks/pre_install.lua")
            ctx.version = "2.2.4"
            RUNTIME.osType = "Linux"
            RUNTIME.archType = "x86_64"

            local result = PLUGIN:PreInstall(ctx)
            assert.is_table(result)
            -- Should respect the env var directly
            assert.is_string(result.url)
            assert.matches("linux_x64", result.url)
        end)
    end)
end)
