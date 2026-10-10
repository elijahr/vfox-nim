-- Tests for Nimony support in vfox-nim
require("spec.helpers")
local utils = require("lib.nim_utils")

describe("Nimony support", function()
    local orig_http_get, orig_json_decode, orig_getenv, orig_url_exists

    local mock_releases = [=[
[
  {
    "tag_name": "nightly-0.6.3-b3806c1ce",
    "name": "Nimony 0.6.3 nightly (2026-10-08)",
    "draft": false,
    "prerelease": true,
    "assets": [
      {
        "name": "nimony-0.6.3-b3806c1ce-linux_amd64.tar.xz",
        "browser_download_url": "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-linux_amd64.tar.xz"
      },
      {
        "name": "nimony-0.6.3-b3806c1ce-linux_arm64.tar.xz",
        "browser_download_url": "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-linux_arm64.tar.xz"
      },
      {
        "name": "nimony-0.6.3-b3806c1ce-macos_arm64.tar.xz",
        "browser_download_url": "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-macos_arm64.tar.xz"
      },
      {
        "name": "nimony-0.6.3-b3806c1ce-windows_amd64.zip",
        "browser_download_url": "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-windows_amd64.zip"
      }
    ]
  },
  {
    "tag_name": "nightly-0.6.2-db9cb13bc",
    "name": "Nimony 0.6.2 nightly (2026-09-15)",
    "draft": false,
    "prerelease": true,
    "assets": [
      {
        "name": "nimony-0.6.2-db9cb13bc-linux_amd64.tar.xz",
        "browser_download_url": "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.2-db9cb13bc/nimony-0.6.2-db9cb13bc-linux_amd64.tar.xz"
      },
      {
        "name": "nimony-0.6.2-db9cb13bc-linux_arm64.tar.xz",
        "browser_download_url": "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.2-db9cb13bc/nimony-0.6.2-db9cb13bc-linux_arm64.tar.xz"
      },
      {
        "name": "nimony-0.6.2-db9cb13bc-macos_arm64.tar.xz",
        "browser_download_url": "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.2-db9cb13bc/nimony-0.6.2-db9cb13bc-macos_arm64.tar.xz"
      },
      {
        "name": "nimony-0.6.2-db9cb13bc-windows_amd64.zip",
        "browser_download_url": "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.2-db9cb13bc/nimony-0.6.2-db9cb13bc-windows_amd64.zip"
      }
    ]
  }
]
]=]

    before_each(function()
        orig_http_get = _G.http.get
        orig_json_decode = _G.json.decode
        orig_getenv = os.getenv
        orig_url_exists = utils.url_exists

        local helpers = require("spec.helpers")
        helpers.reset_mocks()
    end)

    after_each(function()
        _G.http.get = orig_http_get
        _G.json.decode = orig_json_decode
        os.getenv = orig_getenv
        utils.url_exists = orig_url_exists
    end)

    describe("is_nimony_version", function()
        it("identifies 'nimony' and 'nimony-latest'", function()
            assert.is_true(utils.is_nimony_version("nimony"))
            assert.is_true(utils.is_nimony_version("Nimony"))
            assert.is_true(utils.is_nimony_version("nimony-latest"))
            assert.is_true(utils.is_nimony_version("NIMONY-LATEST"))
        end)

        it("identifies ref: variants", function()
            assert.is_true(utils.is_nimony_version("ref:nimony"))
            assert.is_true(utils.is_nimony_version("ref:nimony-latest"))
            assert.is_true(utils.is_nimony_version("ref:nightly-0.6.3-b3806c1ce"))
        end)

        it("identifies versioned nimony strings", function()
            assert.is_true(utils.is_nimony_version("nimony-0.6.3"))
            assert.is_true(utils.is_nimony_version("nimony-0.6.3-b3806c1ce"))
            assert.is_true(utils.is_nimony_version("nightly-0.6.3-b3806c1ce"))
        end)

        it("rejects non-nimony versions", function()
            assert.is_false(utils.is_nimony_version("2.2.4"))
            assert.is_false(utils.is_nimony_version("ref:devel"))
            assert.is_false(utils.is_nimony_version("ref:version-2-2"))
            assert.is_false(utils.is_nimony_version(""))
            assert.is_false(utils.is_nimony_version(nil))
        end)
    end)

    describe("get_nimony_platform_suffix", function()
        it("maps Linux architectures", function()
            assert.are.equal("linux_amd64.tar.xz", utils.get_nimony_platform_suffix("linux", "x86_64"))
            assert.are.equal("linux_arm64.tar.xz", utils.get_nimony_platform_suffix("linux", "aarch64"))
            assert.are.equal("linux_arm64.tar.xz", utils.get_nimony_platform_suffix("linux", "arm64"))
        end)

        it("maps macOS architectures", function()
            assert.are.equal("macos_arm64.tar.xz", utils.get_nimony_platform_suffix("macos", "arm64"))
            assert.is_nil(utils.get_nimony_platform_suffix("macos", "x86_64"))
        end)

        it("maps Windows architectures", function()
            assert.are.equal("windows_amd64.zip", utils.get_nimony_platform_suffix("windows", "x86_64"))
            assert.is_nil(utils.get_nimony_platform_suffix("windows", "i686"))
        end)

        it("returns nil for unsupported combinations", function()
            assert.is_nil(utils.get_nimony_platform_suffix("freebsd", "x86_64"))
            assert.is_nil(utils.get_nimony_platform_suffix("linux", "i686"))
            assert.is_nil(utils.get_nimony_platform_suffix("linux", "armv7"))
        end)
    end)

    describe("find_nimony_url", function()
        before_each(function()
            _G.http.get = function(opts)
                if opts.url:match("nimony%-website/releases") then
                    return {
                        status_code = 200,
                        body = mock_releases,
                    },
                        nil
                end
                return { status_code = 404, body = "{}" }, nil
            end

            local decoded_table = {
                {
                    tag_name = "nightly-0.6.3-b3806c1ce",
                    name = "Nimony 0.6.3 nightly (2026-10-08)",
                    draft = false,
                    prerelease = true,
                    assets = {
                        {
                            name = "nimony-0.6.3-b3806c1ce-linux_amd64.tar.xz",
                            browser_download_url = "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-linux_amd64.tar.xz",
                        },
                        {
                            name = "nimony-0.6.3-b3806c1ce-linux_arm64.tar.xz",
                            browser_download_url = "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-linux_arm64.tar.xz",
                        },
                        {
                            name = "nimony-0.6.3-b3806c1ce-macos_arm64.tar.xz",
                            browser_download_url = "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-macos_arm64.tar.xz",
                        },
                        {
                            name = "nimony-0.6.3-b3806c1ce-windows_amd64.zip",
                            browser_download_url = "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-windows_amd64.zip",
                        },
                    },
                },
                {
                    tag_name = "nightly-0.6.2-db9cb13bc",
                    name = "Nimony 0.6.2 nightly (2026-09-15)",
                    draft = false,
                    prerelease = true,
                    assets = {
                        {
                            name = "nimony-0.6.2-db9cb13bc-linux_amd64.tar.xz",
                            browser_download_url = "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.2-db9cb13bc/nimony-0.6.2-db9cb13bc-linux_amd64.tar.xz",
                        },
                        {
                            name = "nimony-0.6.2-db9cb13bc-linux_arm64.tar.xz",
                            browser_download_url = "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.2-db9cb13bc/nimony-0.6.2-db9cb13bc-linux_arm64.tar.xz",
                        },
                        {
                            name = "nimony-0.6.2-db9cb13bc-macos_arm64.tar.xz",
                            browser_download_url = "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.2-db9cb13bc/nimony-0.6.2-db9cb13bc-macos_arm64.tar.xz",
                        },
                        {
                            name = "nimony-0.6.2-db9cb13bc-windows_amd64.zip",
                            browser_download_url = "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.2-db9cb13bc/nimony-0.6.2-db9cb13bc-windows_amd64.zip",
                        },
                    },
                },
            }
            _G.json.decode = function(_)
                return decoded_table
            end
        end)

        it("resolves latest nimony for Linux x86_64", function()
            local url, tag = utils.find_nimony_url("nimony-latest", "linux", "x86_64")
            assert.are.equal(
                "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-linux_amd64.tar.xz",
                url
            )
            assert.are.equal("nightly-0.6.3-b3806c1ce", tag)
        end)

        it("resolves latest nimony for macOS arm64", function()
            local url, tag = utils.find_nimony_url("nimony", "macos", "arm64")
            assert.are.equal(
                "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-macos_arm64.tar.xz",
                url
            )
            assert.are.equal("nightly-0.6.3-b3806c1ce", tag)
        end)

        it("resolves latest nimony for Windows x86_64", function()
            local url, tag = utils.find_nimony_url("ref:nimony", "windows", "x86_64")
            assert.are.equal(
                "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-windows_amd64.zip",
                url
            )
            assert.are.equal("nightly-0.6.3-b3806c1ce", tag)
        end)

        it("resolves specific version e.g. nimony-0.6.2", function()
            local url, tag = utils.find_nimony_url("nimony-0.6.2", "linux", "x86_64")
            assert.are.equal(
                "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.2-db9cb13bc/nimony-0.6.2-db9cb13bc-linux_amd64.tar.xz",
                url
            )
            assert.are.equal("nightly-0.6.2-db9cb13bc", tag)
        end)

        it("resolves specific nightly tag e.g. nightly-0.6.3-b3806c1ce", function()
            local url, tag = utils.find_nimony_url("nightly-0.6.3-b3806c1ce", "linux", "arm64")
            assert.are.equal(
                "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-linux_arm64.tar.xz",
                url
            )
            assert.are.equal("nightly-0.6.3-b3806c1ce", tag)
        end)

        it("returns nil and helpful error for unsupported platform", function()
            local url, err = utils.find_nimony_url("nimony-latest", "macos", "x86_64")
            assert.is_nil(url)
            assert.is_truthy(err:match("Platform macos/x86_64 is not supported"))
        end)
    end)

    describe("pre_install hook with Nimony", function()
        before_each(function()
            _G.http.get = function(opts)
                if opts.url:match("nimony%-website/releases") then
                    return {
                        status_code = 200,
                        body = mock_releases,
                    },
                        nil
                end
                return { status_code = 404, body = "{}" }, nil
            end

            _G.json.decode = function(_)
                return {
                    {
                        tag_name = "nightly-0.6.3-b3806c1ce",
                        name = "Nimony 0.6.3 nightly (2026-10-08)",
                        draft = false,
                        prerelease = true,
                        assets = {
                            {
                                name = "nimony-0.6.3-b3806c1ce-macos_arm64.tar.xz",
                                browser_download_url = "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-macos_arm64.tar.xz",
                            },
                        },
                    },
                }
            end
        end)

        it("handles nimony-latest request", function()
            dofile("hooks/pre_install.lua")
            ctx.version = "nimony-latest"
            RUNTIME.osType = "Darwin"
            RUNTIME.archType = "arm64"

            local result = PLUGIN:PreInstall(ctx)
            assert.is_table(result)
            assert.are.equal("nimony-latest", result.version)
            assert.are.equal(
                "https://github.com/nim-lang/nimony-website/releases/download/nightly-0.6.3-b3806c1ce/nimony-0.6.3-b3806c1ce-macos_arm64.tar.xz",
                result.url
            )
            assert.is_truthy(result.note:match("Nimony nightly binary"))
        end)

        it("rejects install_method='source' for nimony", function()
            dofile("hooks/pre_install.lua")
            ctx.version = "nimony"
            ctx.options = { install_method = "source" }
            RUNTIME.osType = "Darwin"
            RUNTIME.archType = "arm64"

            local success, err = pcall(function()
                PLUGIN:PreInstall(ctx)
            end)
            assert.is_false(success)
            assert.is_truthy(tostring(err):match("Building Nimony from source is not supported"))
        end)
    end)

    describe("available hook with Nimony", function()
        it("exposes nimony-latest at the top of available versions", function()
            _G.http.get = function(opts)
                if opts.url:match("nimony%-website/releases") then
                    return {
                        status_code = 200,
                        body = mock_releases,
                    },
                        nil
                end
                return {
                    status_code = 200,
                    body = '[{"name":"v2.2.4"},{"name":"v2.2.2"}]',
                },
                    nil
            end

            _G.json.decode = function(str)
                if str == mock_releases then
                    return {
                        { tag_name = "nightly-0.6.3-b3806c1ce" },
                        { tag_name = "nightly-0.6.2-db9cb13bc" },
                    }
                end
                return {
                    { name = "v2.2.4" },
                    { name = "v2.2.2" },
                }
            end

            dofile("hooks/available.lua")
            local result = PLUGIN:Available(ctx)
            assert.is_table(result)
            assert.is_true(#result >= 3)
            local has_latest, has_063, has_specific_nightly = false, false, false
            for _, item in ipairs(result) do
                if item.version == "nimony-latest" then
                    has_latest = true
                end
                if item.version == "nimony-0.6.3" then
                    has_063 = true
                end
                if item.version == "nimony-0.6.3-b3806c1ce" then
                    has_specific_nightly = true
                end
            end
            assert.is_true(has_latest)
            assert.is_true(has_063)
            assert.is_true(has_specific_nightly)
        end)
    end)

    describe("post_install hook with Nimony", function()
        local orig_io_open, orig_io_close, orig_io_popen, post_orig_getenv
        local executed_cmds = {}
        local files_state = {}

        before_each(function()
            _G.PLUGIN = { name = "nim" }
            _G.ctx = {
                sdkInfo = {
                    nim = {
                        name = "nim",
                        version = "nimony-latest",
                        path = "/test/nimony/path",
                    },
                },
            }

            executed_cmds = {}
            files_state = {}

            post_orig_getenv = os.getenv
            os.getenv = function(name)
                if name == "NIM_INSTALL_METHOD" then
                    return "auto"
                end
                return post_orig_getenv(name)
            end

            orig_io_open = io.open
            io.open = function(filepath, mode)
                if files_state[filepath] then
                    return {
                        read = function()
                            return ""
                        end,
                        close = function()
                            return true
                        end,
                        write = function()
                            return true
                        end,
                    }
                end
                return nil
            end

            orig_io_close = io.close
            io.close = function(file)
                if file and file.close then
                    return file:close()
                end
                return true
            end

            orig_io_popen = io.popen
            io.popen = function(cmd)
                table.insert(executed_cmds, cmd)
                if cmd:match("nim.*%-%-version") then
                    return {
                        read = function()
                            return "0.6.3 [macosx; arm64]\n"
                        end,
                        close = function()
                            return true
                        end,
                    }
                end
                if cmd:match("ls %-d .*nimony") then
                    if files_state["/test/nimony/path/nimony"] then
                        return {
                            read = function()
                                return "/test/nimony/path/nimony\n"
                            end,
                            close = function()
                                return true
                            end,
                        }
                    end
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
            io.open = orig_io_open
            io.close = orig_io_close
            io.popen = orig_io_popen
            os.getenv = post_orig_getenv
        end)

        it("symlinks bin/nim -> bin/nimony and verifies installation", function()
            -- Simulate nimony binary present in bin/
            files_state["/test/nimony/path/bin/nimony"] = true

            dofile("hooks/post_install.lua")

            -- On execution, post_install should symlink nim -> nimony
            -- Mock that symlink creates bin/nim
            local orig_popen = io.popen
            io.popen = function(cmd)
                table.insert(executed_cmds, cmd)
                if cmd:match("ln %-sf nimony") then
                    files_state["/test/nimony/path/bin/nim"] = true
                end
                if cmd:match("nim.*%-%-version") then
                    return {
                        read = function()
                            return "0.6.3 [macosx; arm64]\n"
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

            local result = PLUGIN:PostInstall(ctx)
            assert.is_table(result)

            -- Check that chmod +x was run
            local chmod_ran = false
            local symlink_ran = false
            for _, cmd in ipairs(executed_cmds) do
                if cmd:match("chmod %+x") then
                    chmod_ran = true
                end
                if cmd:match("ln %-sf nimony") then
                    symlink_ran = true
                end
            end

            assert.is_true(chmod_ran)
            assert.is_true(symlink_ran)
        end)

        it("restructures nimony subdirectory when extracted inside install path", function()
            -- Simulate nested nimony directory
            files_state["/test/nimony/path/nimony"] = true
            files_state["/test/nimony/path/bin/nimony"] = true
            files_state["/test/nimony/path/bin/nim"] = true

            dofile("hooks/post_install.lua")
            local result = PLUGIN:PostInstall(ctx)
            assert.is_table(result)

            local cp_ran = false
            local rm_ran = false
            for _, cmd in ipairs(executed_cmds) do
                if cmd:match("cp %-R .*/nimony") then
                    cp_ran = true
                end
                if cmd:match("rm %-rf .*/nimony") then
                    rm_ran = true
                end
            end

            assert.is_true(cp_ran)
            assert.is_true(rm_ran)
        end)
    end)
end)
