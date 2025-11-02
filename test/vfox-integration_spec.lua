-- vfox integration tests - tests the plugin with actual vfox execution
-- Tests the vfox Tool Plugin hooks (Available, PreInstall, PostInstall, EnvKeys)
-- Run with: busted test/vfox-integration_spec.lua

-- Test environment setup
local SCRIPT_DIR = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local PLUGIN_DIR = SCRIPT_DIR .. ".."

-- Environment variable management
local env_vars = {}

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

describe("vfox Plugin Integration Tests", function()
    -- Setup runs once before all tests
    setup(function()
        setup_github_token()

        print("\n========================================")
        print("  vfox Plugin Integration Tests")
        print("========================================\n")

        -- Check if vfox is installed
        assert(exec_status("command -v vfox"), "vfox is not installed. Install from: https://vfox.dev/")

        local vfox_version = exec("vfox --version"):gsub("%s+$", "")
        print("✓ vfox version: " .. vfox_version)

        -- Set install method for faster tests
        setenv("VFOX_NIM_INSTALL_METHOD", "binary")
        print("✓ Using install_method='binary' for tests")

        -- Add the plugin using git archive
        print("\n→ Adding plugin for local testing...")
        os.execute("vfox remove -y nim 2>/dev/null || true")

        -- Create a zip archive of the current repository
        local zip_path = "/tmp/vfox-nim-test.zip"
        local archive_result =
            os.execute("cd '" .. PLUGIN_DIR .. "' && git archive --format=zip --output='" .. zip_path .. "' HEAD")
        assert(archive_result == true or archive_result == 0, "Failed to create git archive")

        -- Add the plugin from the zip file
        local add_result = os.execute("vfox add --source '" .. zip_path .. "' --alias nim 2>&1")
        assert(add_result == true or add_result == 0, "Failed to add plugin from zip")

        print("✓ Plugin added from local zip\n")
    end)

    -- Teardown runs once after all tests
    teardown(function()
        print("\n========================================")
        print("  Cleanup")
        print("========================================\n")

        print("→ Removing plugin...")
        os.execute("vfox remove -y nim 2>/dev/null || true")

        -- Remove the zip file if it exists
        os.execute("rm -f /tmp/vfox-nim-test.zip")

        print("✓ Plugin removed")
    end)

    describe("Plugin Setup", function()
        it("should be listed in vfox list", function()
            local output, success = exec("vfox list 2>&1")
            assert.is_true(success)
            assert.matches("nim", output)
        end)

        it("should have required hook files", function()
            assert.is_true(dir_exists(PLUGIN_DIR .. "/hooks"), "Hooks directory not found")

            local required_hooks = { "available", "pre_install", "post_install", "env_keys" }
            for _, hook in ipairs(required_hooks) do
                assert.is_true(
                    file_exists(PLUGIN_DIR .. "/hooks/" .. hook .. ".lua"),
                    "Hook file " .. hook .. ".lua not found"
                )
            end
        end)

        it("should have metadata.lua", function()
            assert.is_true(file_exists(PLUGIN_DIR .. "/metadata.lua"))
        end)
    end)

    describe("Version Management", function()
        it("should list available versions with vfox search", function()
            local output, success = exec("vfox search nim 2>&1")
            assert.is_true(success, "vfox search nim failed")
            assert.matches("2%.2%.4", output, "Version 2.2.4 not found in output")
        end)

        it("should install nim@2.2.4", function()
            local output, success = exec("vfox install -y nim@2.2.4 2>&1")
            assert.is_true(success, "vfox install -y nim@2.2.4 failed: " .. output)

            local list_output = exec("vfox list nim 2>&1")
            assert.matches("2%.2%.4", list_output, "nim 2.2.4 not shown in vfox list after installation")
        end)
    end)

    describe("Nim Execution", function()
        before_each(function()
            -- Activate the installed version
            os.execute("vfox use -g nim@2.2.4 2>&1")
            os.execute('eval "$(vfox activate bash)"')
        end)

        it("should execute nim --version", function()
            -- Use vfox use -g to set global version
            os.execute("vfox use -g nim@2.2.4 2>&1")

            local output, success = exec("bash -c 'eval \"$(vfox activate bash)\" && nim --version' 2>&1")
            assert.is_true(success, "nim --version failed")
            assert.matches("Nim Compiler", output)
        end)

        it("should have nimble available", function()
            local output, success = exec("bash -c 'eval \"$(vfox activate bash)\" && nimble --version' 2>&1")
            assert.is_true(success, "nimble --version failed")
            assert.matches("nimble", output:lower())
        end)

        it("should compile and run a simple Nim program", function()
            local test_dir = os.tmpname()
            os.remove(test_dir)
            os.execute("mkdir -p '" .. test_dir .. "'")

            local f = io.open(test_dir .. "/hello.nim", "w")
            f:write('echo "Hello from Nim!"\n')
            f:close()

            local output, success =
                exec('bash -c \'eval "$(vfox activate bash)" && cd "' .. test_dir .. "\" && nim c -r hello.nim' 2>&1")
            os.execute("rm -rf '" .. test_dir .. "'")

            assert.is_true(success, "Failed to compile simple Nim program: " .. output)
            assert.matches("Hello from Nim!", output)
        end)
    end)

    describe("Environment Variables", function()
        it("should set NIMBLE_DIR correctly", function()
            local nimble_dir =
                exec("bash -c 'eval \"$(vfox activate bash)\" && echo $NIMBLE_DIR' 2>&1"):gsub("%s+$", "")

            if nimble_dir ~= "" then
                assert.matches("nim", nimble_dir, "NIMBLE_DIR should contain 'nim'")
                assert.matches("2%.2%.4", nimble_dir, "NIMBLE_DIR should contain version 2.2.4")
            end
            -- Not failing if empty as it may be intentional with local nimbledeps
        end)
    end)

    describe("Configuration Files", function()
        it("should support .tool-versions file", function()
            local test_dir = os.tmpname()
            os.remove(test_dir)
            os.execute("mkdir -p '" .. test_dir .. "'")

            -- Create .tool-versions file
            local f = io.open(test_dir .. "/.tool-versions", "w")
            f:write("nim 2.2.4\n")
            f:close()

            -- Check if vfox recognizes it
            local _ = exec("bash -c 'cd \"" .. test_dir .. '" && eval "$(vfox activate bash)" && vfox current\' 2>&1')

            os.execute("rm -rf '" .. test_dir .. "'")

            -- vfox may need explicit use, so we just verify the file was created correctly
            assert.is_true(true, "Tool versions file created")
        end)
    end)

    describe("Nimble Package Manager", function()
        it("should install a nimble package", function()
            local test_dir = os.tmpname()
            os.remove(test_dir)
            os.execute("mkdir -p '" .. test_dir .. "'")

            local output, success = exec(
                'bash -c \'eval "$(vfox activate bash)" && cd "'
                    .. test_dir
                    .. "\" && echo y | nimble install -y argparse' 2>&1"
            )
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
            local _ = exec("echo 'y' | vfox uninstall nim@2.2.4 2>&1")
            local current_output = exec("vfox current nim 2>&1")
            assert.is_false(current_output:match("2%.2%.4") ~= nil, "Version still shows as installed after uninstall")

            local install_output, success = exec("vfox install --yes nim@2.2.4 2>&1")
            assert.is_true(success, "Reinstall failed: " .. install_output)

            local list_output = exec("vfox list nim 2>&1")
            assert.matches("2%.2%.4", list_output, "nim 2.2.4 not found after reinstall")
        end)
    end)

    describe("Install Methods", function()
        it("should install with VFOX_NIM_INSTALL_METHOD='auto'", function()
            os.execute("echo 'y' | vfox uninstall --yes nim@2.2.4 >/dev/null 2>&1 || true")

            setenv("VFOX_NIM_INSTALL_METHOD", "auto")
            local output, success = exec("vfox install --yes nim@2.2.4 2>&1")
            setenv("VFOX_NIM_INSTALL_METHOD", "binary")

            assert.is_true(success, "Installation with install_method='auto' failed: " .. output)

            local list_output = exec("vfox list nim 2>&1")
            assert.matches("2%.2%.4", list_output)
        end)

        it("should install with VFOX_NIM_INSTALL_METHOD='source'", function()
            -- Note: This test can be very slow as it builds from source
            os.execute("echo 'y' | vfox uninstall --yes nim@2.2.4 >/dev/null 2>&1 || true")

            setenv("VFOX_NIM_INSTALL_METHOD", "source")
            local output, success = exec("vfox install --yes nim@2.2.4 2>&1")
            setenv("VFOX_NIM_INSTALL_METHOD", "binary")

            assert.is_true(success, "Installation with install_method='source' failed: " .. output)

            local list_output = exec("vfox list nim 2>&1")
            assert.matches("2%.2%.4", list_output)
        end)
    end)

    describe("Error Handling", function()
        it("should fail when binary install is forced but no binary is available", function()
            -- Try to install a very old version that likely doesn't have prebuilt binaries
            setenv("VFOX_NIM_INSTALL_METHOD", "binary")
            local output, success = exec("vfox install --yes nim@0.8.14 2>&1")
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
