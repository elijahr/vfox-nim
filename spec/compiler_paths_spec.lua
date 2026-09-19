-- Unit tests for compiler paths configuration in post_install hook
require("spec.helpers")

describe("post_install compiler paths configuration", function()
    local written_content = {}
    local executed_cmds = {}

    before_each(function()
        _G.PLUGIN = { name = "nim" }
        _G.ctx = {
            sdkInfo = {
                nim = {
                    name = "nim",
                    version = "2.2.8",
                    path = "/test/nim-sdk",
                },
            },
        }

        written_content = {}
        executed_cmds = {}

        _G.os.getenv_orig = _G.os.getenv
        _G.os.getenv = function(name)
            if name == "HOME" then
                return "/tmp/test-home"
            end
            return nil
        end

        _G.io.close_orig = _G.io.close
        _G.io.close = function(file)
            if file and file.close then
                return file:close()
            end
            return true
        end

        _G.test_cfg_content = ""
        _G.test_has_compiler = true
        _G.test_has_lib_compiler = false

        _G.io.open_orig = _G.io.open
        _G.io.open = function(filepath, mode)
            if filepath:match("/bin/nim$") or filepath:match("/bin/nim%.exe$") then
                return {
                    close = function()
                        return true
                    end,
                }
            end

            if filepath:match("config/nim%.cfg$") then
                if mode == "r" then
                    return {
                        read = function(_, format)
                            if format == "*a" then
                                return _G.test_cfg_content
                            end
                            return ""
                        end,
                        close = function()
                            return true
                        end,
                    }
                elseif mode == "a" or mode == "w" then
                    return {
                        write = function(_, content)
                            table.insert(written_content, content)
                            _G.test_cfg_content = _G.test_cfg_content .. content
                            return true
                        end,
                        close = function()
                            return true
                        end,
                    }
                end
            end

            if filepath:match("/compiler/ast%.nim$") then
                if filepath:match("/lib/compiler/ast%.nim$") then
                    if _G.test_has_lib_compiler then
                        return {
                            close = function()
                                return true
                            end,
                        }
                    end
                    return nil
                else
                    if _G.test_has_compiler then
                        return {
                            close = function()
                                return true
                            end,
                        }
                    end
                    return nil
                end
            end

            return nil
        end

        _G.io.popen_orig = _G.io.popen
        _G.io.popen = function(cmd)
            table.insert(executed_cmds, cmd)
            if cmd:match("nim.*%-%-version") then
                return {
                    read = function()
                        return "Nim Compiler Version 2.2.8"
                    end,
                    close = function()
                        return true
                    end,
                }
            end
            return {
                read = function()
                    return ""
                end,
                close = function()
                    return true
                end,
            }
        end
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
    end)

    it('appends path = "$nim" to config/nim.cfg when not present', function()
        _G.test_cfg_content = 'path="$lib/pure"\n'
        dofile("hooks/post_install.lua")

        PLUGIN:PostInstall(ctx)

        assert.is_true(#written_content > 0)
        local joined = table.concat(written_content, "")
        assert.matches('path = "%$nim"', joined)
    end)

    it('does not append path = "$nim" if already present in config/nim.cfg', function()
        _G.test_cfg_content = 'path="$lib/pure"\npath = "$nim"\n'
        dofile("hooks/post_install.lua")

        PLUGIN:PostInstall(ctx)

        assert.equal(0, #written_content)
    end)

    it('does not append if path = "$lib/.." is already present', function()
        _G.test_cfg_content = 'path="$lib/pure"\npath="$lib/.."\n'
        dofile("hooks/post_install.lua")

        PLUGIN:PostInstall(ctx)

        assert.equal(0, #written_content)
    end)

    it("creates relative symlink lib/compiler -> ../compiler when compiler sources exist", function()
        _G.test_has_compiler = true
        _G.test_has_lib_compiler = false

        dofile("hooks/post_install.lua")
        PLUGIN:PostInstall(ctx)

        local found_symlink_cmd = false
        for _, cmd in ipairs(executed_cmds) do
            if cmd:match("ln %-sf %.%./compiler") then
                found_symlink_cmd = true
                break
            end
        end
        assert.is_true(found_symlink_cmd, "Expected ln -sf ../compiler command to be executed")
    end)

    it("does not recreate symlink if lib/compiler already has ast.nim", function()
        _G.test_has_compiler = true
        _G.test_has_lib_compiler = true

        dofile("hooks/post_install.lua")
        PLUGIN:PostInstall(ctx)

        local found_symlink_cmd = false
        for _, cmd in ipairs(executed_cmds) do
            if cmd:match("ln %-sf %.%./compiler") then
                found_symlink_cmd = true
                break
            end
        end
        assert.is_false(found_symlink_cmd, "Should not create symlink when lib/compiler/ast.nim already exists")
    end)
end)
