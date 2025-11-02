-- Smoke tests for vfox-nim hooks
-- These just verify hooks can be loaded and basic functionality works
require("spec.helpers")

describe("vfox-nim smoke tests", function()
    before_each(function()
        -- Reset PLUGIN
        _G.PLUGIN = { name = "nim" }

        -- Set up default ctx
        _G.ctx = {
            version = "2.2.4",
            path = "/test/path",
            sdkInfo = {
                nim = {
                    name = "nim",
                    version = "2.2.4",
                    path = "/test/path",
                },
            },
        }

        -- Mock os.getenv for tests
        _G.os.getenv_orig = _G.os.getenv
        _G.os.getenv = function(name)
            if name == "PWD" then
                return "/test/workdir"
            end
            return nil
        end
    end)

    after_each(function()
        if _G.os.getenv_orig then
            _G.os.getenv = _G.os.getenv_orig
        end
    end)

    describe("available hook", function()
        it("can be loaded without errors", function()
            local success = pcall(function()
                dofile("hooks/available.lua")
            end)
            assert.is_true(success)
        end)

        it("returns a table", function()
            -- Mock GitHub API response
            local http = require("http")
            http.get = function(opts)
                return {
                    status_code = 200,
                    body = '[{"name":"v2.2.4"},{"name":"v2.2.2"},{"name":"v2.0.0"}]',
                },
                    nil
            end

            local json = require("json")
            json.decode = function(str)
                return {
                    { name = "v2.2.4" },
                    { name = "v2.2.2" },
                    { name = "v2.0.0" },
                }
            end

            dofile("hooks/available.lua")
            local result = PLUGIN:Available(ctx)
            assert.is_table(result)
        end)
    end)

    describe("pre_install hook", function()
        it("can be loaded without errors", function()
            local success = pcall(function()
                dofile("hooks/pre_install.lua")
            end)
            assert.is_true(success)
        end)

        it("returns download info for stable version", function()
            -- Mock URL existence check to return true
            local http = require("http")
            http.head = function(opts)
                return { status_code = 200 }, nil
            end

            dofile("hooks/pre_install.lua")
            ctx.version = "2.2.4"
            RUNTIME.osType = "Linux"
            RUNTIME.archType = "x86_64"

            local result = PLUGIN:PreInstall(ctx)
            assert.is_table(result)
            assert.is_string(result.url)
            assert.is_string(result.version)
        end)
    end)

    describe("post_install hook", function()
        it("can be loaded without errors", function()
            local success = pcall(function()
                dofile("hooks/post_install.lua")
            end)
            assert.is_true(success)
        end)
    end)

    describe("env_keys hook", function()
        it("can be loaded without errors", function()
            local success = pcall(function()
                dofile("hooks/env_keys.lua")
            end)
            assert.is_true(success)
        end)

        it("returns environment variables array", function()
            dofile("hooks/env_keys.lua")
            local result = PLUGIN:EnvKeys(ctx)
            assert.is_table(result)
        end)

        it("sets PATH", function()
            dofile("hooks/env_keys.lua")
            local result = PLUGIN:EnvKeys(ctx)

            local found_path = false
            for _, env_var in ipairs(result) do
                if env_var.key == "PATH" then
                    found_path = true
                    assert.is_string(env_var.value)
                end
            end
            assert.is_true(found_path, "Should set PATH")
        end)

        it("sets NIMBLE_DIR when no local nimbledeps", function()
            dofile("hooks/env_keys.lua")
            local result = PLUGIN:EnvKeys(ctx)

            local found_nimble_dir = false
            for _, env_var in ipairs(result) do
                if env_var.key == "NIMBLE_DIR" then
                    found_nimble_dir = true
                end
            end
            assert.is_true(found_nimble_dir, "Should set NIMBLE_DIR")
        end)
    end)

    describe("lib/nim_utils", function()
        it("can be loaded without errors", function()
            local success, utils = pcall(function()
                return require("lib.nim_utils")
            end)
            assert.is_true(success)
            assert.is_table(utils)
        end)

        it("has expected functions", function()
            local utils = require("lib.nim_utils")
            assert.is_function(utils.normalize_os)
            assert.is_function(utils.normalize_arch)
            assert.is_function(utils.is_stable_version)
            assert.is_function(utils.is_ref_version)
        end)

        it("normalizes OS names", function()
            local utils = require("lib.nim_utils")
            assert.equal("macos", utils.normalize_os("Darwin"))
            assert.equal("linux", utils.normalize_os("Linux"))
            assert.equal("windows", utils.normalize_os("Windows_NT"))
        end)

        it("normalizes architectures", function()
            local utils = require("lib.nim_utils")
            assert.equal("x86_64", utils.normalize_arch("amd64"))
            assert.equal("x86_64", utils.normalize_arch("x86_64"))
            assert.equal("i686", utils.normalize_arch("x86"))
            assert.equal("arm64", utils.normalize_arch("arm64"))
        end)

        it("detects stable versions", function()
            local utils = require("lib.nim_utils")
            assert.is_true(utils.is_stable_version("2.2.4"))
            assert.is_true(utils.is_stable_version("1.6.14"))
            assert.is_false(utils.is_stable_version("ref:devel"))
        end)

        it("detects ref versions", function()
            local utils = require("lib.nim_utils")
            assert.is_true(utils.is_ref_version("ref:devel"))
            assert.is_true(utils.is_ref_version("ref:version-2-2"))
            assert.is_false(utils.is_ref_version("2.2.4"))
        end)
    end)
end)
