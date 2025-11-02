-- Unit tests for install_method behavior in post_install hook
require("spec.helpers")

describe("post_install install_method behavior", function()
    before_each(function()
        -- Reset PLUGIN
        _G.PLUGIN = { name = "nim" }

        -- Set up default ctx
        _G.ctx = {
            sdkInfo = {
                nim = {
                    name = "nim",
                    version = "2.2.4",
                    path = "/test/path",
                },
            },
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
            if name == "MISE_VERBOSE" then
                return nil
            end
            return nil
        end

        -- Mock io.close
        _G.io.close_orig = _G.io.close
        _G.io.close = function(file)
            if file and file.close then
                return file:close()
            end
            return true
        end

        -- Mock io.open to simulate file system
        _G.io.open_orig = _G.io.open
        _G.io.open = function(filepath, mode)
            -- Create a mock file handle
            local mock_file = {
                close = function(self)
                    return true
                end,
                read = function(self, format)
                    return ""
                end,
                write = function(self, content)
                    return true
                end,
            }

            -- Simulate binary exists
            if filepath:match("/bin/nim$") or filepath:match("/bin/nim%.exe$") then
                if _G.test_has_binary then
                    return mock_file
                else
                    return nil
                end
            end
            -- Simulate build scripts
            if filepath:match("build_all%.sh$") or filepath:match("build_all%.bat$") then
                if _G.test_has_build_script then
                    return mock_file
                else
                    return nil
                end
            end
            -- Simulate config file
            if filepath:match("config/build_config%.txt$") then
                return mock_file
            end
            -- Default: file doesn't exist
            return nil
        end

        -- Mock io.popen
        _G.io.popen_orig = _G.io.popen
        _G.io.popen = function(cmd)
            if cmd:match("find .* %-name") then
                -- Simulate no subdirectory found
                return {
                    read = function()
                        return ""
                    end,
                    close = function()
                        return true
                    end,
                }
            end
            if cmd:match("nim.*%-%-version") then
                -- Simulate nim --version
                return {
                    read = function()
                        return "Nim Compiler Version 2.2.4"
                    end,
                    close = function()
                        return true
                    end,
                }
            end
            -- Default
            return {
                read = function()
                    return ""
                end,
                close = function()
                    return true
                end,
            }
        end

        -- Mock os.execute
        _G.os.execute_orig = _G.os.execute
        _G.os.execute = function(cmd)
            return 0 -- Success
        end

        -- Default test state
        _G.test_has_binary = true
        _G.test_has_build_script = false
    end)

    after_each(function()
        if _G.os.getenv_orig then
            _G.os.getenv = _G.os.getenv_orig
        end
        if _G.io.close_orig then
            _G.io.close = _G.io.close_orig
        end
        if _G.io.open_orig then
            _G.io.open = _G.io.open_orig
        end
        if _G.io.popen_orig then
            _G.io.popen = _G.io.popen_orig
        end
        if _G.os.execute_orig then
            _G.os.execute = _G.os.execute_orig
        end
    end)

    describe("when binary exists", function()
        it("uses the binary with install_method='auto'", function()
            _G.test_has_binary = true

            dofile("hooks/post_install.lua")
            local result = PLUGIN:PostInstall(ctx)
            assert.is_table(result)
        end)

        it("uses the binary with install_method='binary'", function()
            _G.test_has_binary = true
            _G.os.getenv = function(name)
                if name == "VFOX_NIM_INSTALL_METHOD" then
                    return "binary"
                end
                return nil
            end

            dofile("hooks/post_install.lua")
            local result = PLUGIN:PostInstall(ctx)
            assert.is_table(result)
        end)

        it("uses the binary with install_method='source'", function()
            _G.test_has_binary = true
            _G.os.getenv = function(name)
                if name == "VFOX_NIM_INSTALL_METHOD" then
                    return "source"
                end
                return nil
            end

            dofile("hooks/post_install.lua")
            local result = PLUGIN:PostInstall(ctx)
            assert.is_table(result)
        end)
    end)

    describe("when binary missing but build script exists", function()
        it("errors with install_method='binary'", function()
            _G.test_has_binary = false
            _G.test_has_build_script = true
            _G.os.getenv = function(name)
                if name == "VFOX_NIM_INSTALL_METHOD" then
                    return "binary"
                end
                return nil
            end

            dofile("hooks/post_install.lua")
            local success, err = pcall(function()
                PLUGIN:PostInstall(ctx)
            end)

            assert.is_false(success)
            assert.matches("Binary installation expected", err)
            assert.matches("install_method='binary'", err)
        end)
    end)
end)
