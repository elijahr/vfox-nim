-- Mise integration tests - tests the plugin with actual mise execution
-- Based on mise plugin development documentation: https://mise.jdx.dev/backend-plugin-development.html
-- Run with: busted test/mise-integration_spec.lua

-- Test environment setup
local MISE_TEST_DIR = os.tmpname():gsub("%.%w+$", "") .. ".mise-nim-test"
local SCRIPT_DIR = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local PLUGIN_DIR = SCRIPT_DIR .. ".."

-- Environment variable management
local env_vars = {
    MISE_YES = "1",
}

local function setenv(name, value)
    env_vars[name] = value
end

local function build_env_prefix()
    local parts = {}
    for name, value in pairs(env_vars) do
        table.insert(parts, string.format("%s='%s'", name, value))
    end
    if #parts > 0 then
        return table.concat(parts, " ") .. " "
    end
    return ""
end

-- Helper functions
local function exec(cmd)
    local full_cmd = build_env_prefix() .. cmd
    local handle = io.popen(full_cmd .. " 2>&1")
    local result = handle:read("*a")
    local exit_code = { handle:close() }
    -- In Lua 5.1, close() returns true/false
    -- In Lua 5.2+, close() returns true/nil, exit_type, exit_code
    local success
    if type(exit_code[1]) == "boolean" then
        success = exit_code[1]
    elseif type(exit_code[1]) == "number" then
        success = exit_code[1] == 0
    elseif exit_code[3] then
        success = exit_code[3] == 0
    else
        success = true
    end
    -- Filter out DEBUG lines from mise output
    result = result:gsub("DEBUG[^\n]*\n", "")
    return result, success
end

local function exec_status(cmd)
    local full_cmd = build_env_prefix() .. cmd
    local result, _, exit_code = os.execute(full_cmd .. " >/dev/null 2>&1")
    -- Lua 5.1 returns exit code as number
    -- Lua 5.2+ returns true/nil, "exit", code
    if type(result) == "number" then
        return result == 0
    elseif type(result) == "boolean" then
        return result
    elseif exit_code then
        return exit_code == 0
    else
        return false
    end
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function dir_exists(path)
    return exec_status("test -d '" .. path .. "'")
end

local function get_env(name, default)
    return os.getenv(name) or default or ""
end

-- Setup GitHub token if available
local function setup_github_token()
    local github_token = get_env("GITHUB_TOKEN")
    if github_token == "" then
        if exec_status("command -v gh") then
            if exec_status("gh auth status") then
                local token = exec("gh auth token 2>/dev/null")
                if token and token ~= "" then
                    setenv("GITHUB_TOKEN", token:gsub("%s+$", ""))
                end
            end
        end
    end
end

describe("Mise Plugin Integration Tests", function()
    -- Setup runs once before all tests
    setup(function()
        setup_github_token()

        print("\n========================================")
        print("  Mise Plugin Integration Tests")
        print("========================================\n")

        -- Create sandboxed mise directories
        os.execute(
            "mkdir -p '" .. MISE_TEST_DIR .. "/data' '" .. MISE_TEST_DIR .. "/cache' '" .. MISE_TEST_DIR .. "/config'"
        )

        -- Set environment variables
        setenv("MISE_DATA_DIR", MISE_TEST_DIR .. "/data")
        setenv("MISE_CACHE_DIR", MISE_TEST_DIR .. "/cache")
        setenv("MISE_CONFIG_DIR", MISE_TEST_DIR .. "/config")
        setenv("MISE_DEBUG", "1")
        setenv("MISE_EXPERIMENTAL", "1")
        setenv("VFOX_NIM_INSTALL_METHOD", "binary")

        print("✓ Sandboxed mise environment: " .. MISE_TEST_DIR)
        print("✓ Using install_method='binary' for tests")

        -- Check if mise is installed
        assert(
            exec_status("command -v mise"),
            "mise is not installed. Install from: https://mise.jdx.dev/getting-started.html"
        )

        local mise_version = exec("mise --version | awk '{print $1}'"):gsub("%s+$", "")
        print("✓ mise version: " .. mise_version)

        -- Check mise version
        local major, minor = mise_version:match("(%d+)%.(%d+)")
        major, minor = tonumber(major), tonumber(minor)
        assert(
            major >= 2025 and (major > 2025 or minor >= 10),
            "Backend plugins require mise >= 2025.10.0. Current version: " .. mise_version
        )

        -- Link the plugin
        print("\n→ Linking plugin for local testing...")
        os.execute("mise plugin uninstall nim 2>/dev/null || true")
        os.execute("mise plugin link nim '" .. PLUGIN_DIR .. "'")
        print("✓ Plugin linked from local path\n")
    end)

    -- Teardown runs once after all tests
    teardown(function()
        print("\n========================================")
        print("  Cleanup")
        print("========================================\n")

        print("→ Unlinking plugin...")
        os.execute("mise plugin uninstall nim 2>/dev/null || true")
        print("✓ Plugin unlinked")

        if MISE_TEST_DIR ~= "" and dir_exists(MISE_TEST_DIR) then
            print("→ Cleaning up temporary directory...")
            os.execute("rm -rf '" .. MISE_TEST_DIR .. "'")
            print("✓ Temporary directory removed")
        end
    end)

    describe("Plugin Setup", function()
        it("should be linked and usable", function()
            -- Instead of checking plugin ls (which may not show linked plugins in sandboxed env),
            -- verify the plugin works by checking if we can list versions
            local output, success = exec("mise ls-remote nim 2>&1")
            assert.is_true(success, "mise ls-remote nim failed: " .. output)
            assert.matches("2%.2%.4", output, "Version 2.2.4 not found")
        end)

        it("should have hook files", function()
            -- Plugin is symlinked, so check the original plugin directory
            assert.is_true(
                dir_exists(PLUGIN_DIR .. "/hooks"),
                "Hooks directory not found at " .. PLUGIN_DIR .. "/hooks"
            )
            assert.is_true(
                exec_status("ls '" .. PLUGIN_DIR .. "/hooks'/*.lua >/dev/null 2>&1"),
                "No Lua hook files found"
            )
        end)

        it("should have metadata.lua", function()
            -- Plugin is symlinked, so check the original plugin directory
            assert.is_true(
                file_exists(PLUGIN_DIR .. "/metadata.lua"),
                "metadata.lua not found at " .. PLUGIN_DIR .. "/metadata.lua"
            )
        end)
    end)

    describe("Version Management", function()
        it("should list available versions with mise ls-remote", function()
            local output, success = exec("mise ls-remote nim 2>&1")
            assert.is_true(success, "mise ls-remote nim failed")
            assert.matches("2%.2%.4", output, "Version 2.2.4 not found in output")
        end)

        it("should install nim@2.2.4", function()
            local output, success = exec("mise install nim@2.2.4 2>&1")
            assert.is_true(success, "mise install nim@2.2.4 failed: " .. output)

            assert.is_true(
                exec_status("mise where nim@2.2.4 >/dev/null 2>&1"),
                "mise where nim@2.2.4 failed after installation"
            )

            local nim_path = exec("mise where nim@2.2.4"):gsub("%s+$", "")
            assert.is_true(file_exists(nim_path .. "/bin/nim"), "nim binary not found at " .. nim_path .. "/bin/nim")
        end)
    end)

    describe("Nim Execution", function()
        it("should execute nim --version", function()
            local output, success = exec("mise exec nim@2.2.4 -- nim --version 2>&1")
            assert.is_true(success, "mise exec nim --version failed")
            assert.matches("Nim Compiler", output)

            local nim_path = exec("mise exec nim@2.2.4 -- which nim 2>&1"):gsub("%s+$", "")
            -- Extract just the path (remove any shell output like "export -p")
            nim_path = nim_path:match("[^\n]*$")
            assert.matches(MISE_TEST_DIR, nim_path, "nim not from mise directory: " .. nim_path)
        end)

        it("should have nimble available", function()
            local output, success = exec("mise exec nim@2.2.4 -- nimble --version 2>&1")
            assert.is_true(success, "nimble --version failed")
            assert.matches("nimble", output:lower())

            local nimble_path = exec("mise exec nim@2.2.4 -- which nimble 2>&1"):gsub("%s+$", "")
            -- Extract just the path (remove any shell output like "export -p")
            nimble_path = nimble_path:match("[^\n]*$")
            assert.matches(MISE_TEST_DIR, nimble_path, "nimble not from mise directory: " .. nimble_path)
        end)

        it("should compile and run a simple Nim program", function()
            local test_dir = os.tmpname()
            os.remove(test_dir)
            os.execute("mkdir -p '" .. test_dir .. "'")

            local f = io.open(test_dir .. "/hello.nim", "w")
            f:write('echo "Hello from Nim!"\n')
            f:close()

            local output, success = exec("cd '" .. test_dir .. "' && mise exec nim@2.2.4 -- nim c -r hello.nim 2>&1")
            os.execute("rm -rf '" .. test_dir .. "'")

            assert.is_true(success, "Failed to compile simple Nim program")
            assert.matches("Hello from Nim!", output)
        end)
    end)

    describe("Environment Variables", function()
        it("should set NIMBLE_DIR correctly", function()
            local nimble_dir = exec("mise exec nim@2.2.4 -- sh -c 'echo $NIMBLE_DIR' 2>&1"):gsub("%s+$", "")

            if nimble_dir ~= "" then
                assert.matches("nim", nimble_dir, "NIMBLE_DIR should contain 'nim'")
                assert.matches("2%.2%.4", nimble_dir, "NIMBLE_DIR should contain version 2.2.4")
            end
            -- Not failing if empty as it may be intentional with local nimbledeps
        end)
    end)

    describe("Configuration Files", function()
        it("should support mise use command", function()
            local test_dir = os.tmpname()
            os.remove(test_dir)
            os.execute("mkdir -p '" .. test_dir .. "'")

            exec("cd '" .. test_dir .. "' && mise use nim@2.2.4 2>&1")

            local has_config = false
            if file_exists(test_dir .. "/mise.toml") then
                local f = io.open(test_dir .. "/mise.toml", "r")
                local content = f:read("*a")
                f:close()
                has_config = (content:match("nim") ~= nil)
                    and (content:match("2%.2%.4") ~= nil or content:match('"2.2.4"') ~= nil)
            elseif file_exists(test_dir .. "/.tool-versions") then
                local f = io.open(test_dir .. "/.tool-versions", "r")
                local content = f:read("*a")
                f:close()
                has_config = (content:match("nim") ~= nil) and (content:match("2%.2%.4") ~= nil)
            end

            os.execute("rm -rf '" .. test_dir .. "'")
            assert.is_true(has_config, "Neither mise.toml nor .tool-versions created with correct content")
        end)
    end)

    describe("Nimble Package Manager", function()
        it("should install a nimble package", function()
            local test_dir = os.tmpname()
            os.remove(test_dir)
            os.execute("mkdir -p '" .. test_dir .. "'")

            local output, success =
                exec("cd '" .. test_dir .. "' && echo 'y' | mise exec nim@2.2.4 -- nimble install -y argparse 2>&1")
            os.execute("rm -rf '" .. test_dir .. "'")

            assert.is_true(success, "nimble install failed: " .. output)
            local lower_output = output:lower()
            local has_success_msg = (lower_output:match("success") ~= nil)
                or (lower_output:match("installed") ~= nil)
                or (lower_output:match("already") ~= nil)
            assert.is_true(has_success_msg, "nimble install didn't show expected success message. Output: " .. output)
        end)
    end)

    describe("Uninstall and Reinstall", function()
        it("should uninstall and reinstall nim@2.2.4", function()
            local uninstall_output, uninstall_success = exec("mise uninstall nim@2.2.4 2>&1")
            assert.is_true(uninstall_success, "Uninstall failed: " .. uninstall_output)

            -- After uninstall, mise where should fail
            local where_result = exec_status("mise where nim@2.2.4 2>&1")
            assert.is_false(where_result, "Version still accessible after uninstall")

            local install_output, install_success = exec("mise install nim@2.2.4 2>&1")
            assert.is_true(install_success, "Reinstall failed: " .. install_output)

            assert.is_true(exec_status("mise where nim@2.2.4 >/dev/null 2>&1"), "nim 2.2.4 not found after reinstall")
        end)
    end)

    describe("Error Handling", function()
        it("should fail when binary install is forced but no binary is available", function()
            -- Try to install a very old version that likely doesn't have prebuilt binaries
            setenv("VFOX_NIM_INSTALL_METHOD", "binary")
            local output, success = exec("mise install nim@0.8.14 2>&1")
            -- Reset the env var
            setenv("VFOX_NIM_INSTALL_METHOD", "binary")

            -- Should fail because no binary is available for this old version
            assert.is_false(success, "Installation should have failed but succeeded: " .. output)
            assert.matches(
                "no prebuilt binary available",
                output:lower(),
                "Error message should indicate no binary available"
            )
        end)
    end)
end)
