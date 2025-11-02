-- Unit tests for mise_env hook
require("spec.helpers")

describe("mise_env hook", function()
    before_each(function()
        -- Reset PLUGIN
        _G.PLUGIN = { name = "nim" }

        -- Set up default ctx with options
        _G.ctx = {
            options = {},
        }
    end)

    describe("install_method configuration", function()
        it("can be loaded without errors", function()
            local success = pcall(function()
                dofile("hooks/mise_env.lua")
            end)
            assert.is_true(success)
        end)

        it("returns environment variables array", function()
            dofile("hooks/mise_env.lua")
            local result = PLUGIN:MiseEnv(ctx)
            assert.is_table(result)
        end)

        it("defaults to 'auto' when no install_method specified", function()
            dofile("hooks/mise_env.lua")
            ctx.options = {}
            local result = PLUGIN:MiseEnv(ctx)

            -- Find VFOX_NIM_INSTALL_METHOD in result
            local found = false
            for _, env_var in ipairs(result) do
                if env_var.key == "VFOX_NIM_INSTALL_METHOD" then
                    assert.equal("auto", env_var.value)
                    found = true
                end
            end
            assert.is_true(found, "Should set VFOX_NIM_INSTALL_METHOD")
        end)

        it("accepts 'auto' as install_method", function()
            dofile("hooks/mise_env.lua")
            ctx.options = { install_method = "auto" }
            local result = PLUGIN:MiseEnv(ctx)

            local found = false
            for _, env_var in ipairs(result) do
                if env_var.key == "VFOX_NIM_INSTALL_METHOD" then
                    assert.equal("auto", env_var.value)
                    found = true
                end
            end
            assert.is_true(found)
        end)

        it("accepts 'binary' as install_method", function()
            dofile("hooks/mise_env.lua")
            ctx.options = { install_method = "binary" }
            local result = PLUGIN:MiseEnv(ctx)

            local found = false
            for _, env_var in ipairs(result) do
                if env_var.key == "VFOX_NIM_INSTALL_METHOD" then
                    assert.equal("binary", env_var.value)
                    found = true
                end
            end
            assert.is_true(found)
        end)

        it("accepts 'source' as install_method", function()
            dofile("hooks/mise_env.lua")
            ctx.options = { install_method = "source" }
            local result = PLUGIN:MiseEnv(ctx)

            local found = false
            for _, env_var in ipairs(result) do
                if env_var.key == "VFOX_NIM_INSTALL_METHOD" then
                    assert.equal("source", env_var.value)
                    found = true
                end
            end
            assert.is_true(found)
        end)

        it("rejects invalid install_method values", function()
            dofile("hooks/mise_env.lua")
            ctx.options = { install_method = "invalid" }

            local success, err = pcall(function()
                PLUGIN:MiseEnv(ctx)
            end)

            assert.is_false(success)
            assert.is_not_nil(err)
            assert.matches("Invalid install_method", err)
        end)

        it("provides helpful error message for invalid values", function()
            dofile("hooks/mise_env.lua")
            ctx.options = { install_method = "foobar" }

            local success, err = pcall(function()
                PLUGIN:MiseEnv(ctx)
            end)

            assert.is_false(success)
            assert.matches("foobar", err)
            assert.matches("auto", err)
            assert.matches("binary", err)
            assert.matches("source", err)
        end)
    end)
end)
