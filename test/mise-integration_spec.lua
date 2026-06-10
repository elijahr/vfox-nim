-- Mise integration tests - tests the plugin with actual mise execution
-- Based on mise plugin development documentation: https://mise.jdx.dev/backend-plugin-development.html
-- Run with: busted test/mise-integration_spec.lua

-- Test environment setup
local IS_WINDOWS = package.config:sub(1, 1) == "\\"

-- On Windows the busted Lua is NATIVE MinGW Lua, so io.popen/os.execute spawn
-- cmd.exe (NOT bash). The previous `bash -c '<posix>'` inline approach FAILED:
-- cmd.exe parses the string first and mangles the nested quotes ("unexpected EOF").
--
-- The robust approach used here is a temp-script file: the full POSIX command
-- string is written verbatim to a unique, cwd-relative script (e.g.
-- ./.vfox-spawn-<n>.sh) and spawned via `bash <script>`. cmd.exe then sees only
-- `bash .vfox-spawn-N.sh` -- no nested quoting to mangle. The script is written in
-- binary mode with bare "\n" line endings (no "\r") so bash doesn't choke, and is
-- always removed afterward (os.remove). A cwd-relative name avoids all
-- Windows<->POSIX path translation: native-Windows Lua's cwd is the workspace and
-- the bash spawned by cmd.exe inherits it, so the same relative path resolves
-- identically for the Lua writer and the bash reader.
--
-- On non-Windows the EXACT prior direct-execution path is preserved (no temp file):
-- the command already runs through /bin/sh, so macOS/Linux behavior is unchanged.

-- Module-level counter guaranteeing unique temp-script names across spawns.
local spawn_counter = 0

-- Shared Windows-only temp-script runner. `cmd` is the fully-composed POSIX
-- command string (build_env_prefix() + caller command + any sentinel/redirects),
-- UNCHANGED in content. `want_output` selects capture mode:
--   want_output=true  -> returns (captured_stdout_stderr, success)
--   want_output=false -> returns ("", success) where success is the exit status
-- On Windows the command is run via a temp script; on non-Windows it runs directly.
local function run_posix(cmd, want_output)
    if IS_WINDOWS then
        spawn_counter = spawn_counter + 1
        local script_relpath = "./.vfox-spawn-" .. os.time() .. "-" .. spawn_counter .. ".sh"
        -- Binary mode + bare "\n" endings so bash never sees a stray "\r".
        local script = io.open(script_relpath, "wb")
        script:write("#!/usr/bin/env bash\n")
        script:write(cmd)
        script:write("\n")
        script:close()

        local output, success
        if want_output then
            local handle = io.popen("bash " .. script_relpath .. " 2>&1")
            output = handle:read("*a")
            -- LuaJIT close() returns only `true`; callers that need real exit
            -- status (exec) parse the sentinel from `output` instead.
            success = handle:close() and true or false
        else
            local result, _, exit_code = os.execute("bash " .. script_relpath)
            output = ""
            if type(result) == "number" then
                success = result == 0
            elseif type(result) == "boolean" then
                success = result
            elseif exit_code then
                success = exit_code == 0
            else
                success = false
            end
        end

        os.remove(script_relpath)
        return output, success
    end

    -- Non-Windows: direct execution, byte-for-byte the prior behavior.
    if want_output then
        local handle = io.popen(cmd .. " 2>&1")
        local output = handle:read("*a")
        local success = handle:close() and true or false
        return output, success
    end

    local result, _, exit_code = os.execute(cmd)
    if type(result) == "number" then
        return "", result == 0
    elseif type(result) == "boolean" then
        return "", result
    elseif exit_code then
        return "", exit_code == 0
    end
    return "", false
end

-- Run a POSIX command, ignoring its result. On Windows it routes through the
-- temp-script mechanism; on non-Windows it runs directly via os.execute.
local function raw_execute(cmd)
    run_posix(cmd, false)
end

-- Compute the base temp directory for the sandbox. os.tmpname() returns native
-- Windows names (e.g. \s7uk.) that are unusable as POSIX paths / MISE_DATA_DIR,
-- so on Windows we derive a clean, unique POSIX directory via `mktemp -d` run
-- through the bash wrapper. On non-Windows we keep the existing os.tmpname()
-- approach so macOS/Linux behavior is byte-for-byte identical.
local function make_test_base_dir()
    if IS_WINDOWS then
        local dir = run_posix("mktemp -d", true)
        dir = (dir or ""):gsub("%s+$", "")
        return dir .. "/mise-nim-test"
    end
    return os.tmpname():gsub("%.%w+$", "") .. ".mise-nim-test"
end

-- Create a unique per-test temp directory and return its POSIX path. On Windows
-- this uses `mktemp -d` (os.tmpname() yields unusable native paths); on Unix it
-- preserves the os.tmpname()-based approach.
local function make_temp_dir()
    if IS_WINDOWS then
        local dir = run_posix("mktemp -d", true)
        return (dir or ""):gsub("%s+$", "")
    end
    local dir = os.tmpname()
    os.remove(dir)
    return dir
end

local MISE_TEST_DIR = make_test_base_dir()
local SCRIPT_DIR = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local PLUGIN_DIR = SCRIPT_DIR .. ".."

-- Environment variable management
local env_vars = {
    MISE_YES = "1",
}

local function setenv(name, value)
    env_vars[name] = value
end

-- Ambient variables that leak the developer's GLOBALLY-active mise/nim into the
-- sandbox and break hermeticity. mise's shell activation exports these into every
-- interactive shell (and thus into the busted process), so a child `mise exec`
-- would otherwise resolve the developer's global nim (e.g. 2.2.10) and its
-- NIMBLE_DIR instead of the sandbox-installed nim@2.2.4. We scrub them for every
-- command so the only mise state in scope is the sandbox configured via env_vars.
local SCRUBBED_ENV_VARS = {
    "NIMBLE_DIR",
    "MISE_SHELL",
    "MISE_DATA_DIR",
    "MISE_CACHE_DIR",
    "MISE_CONFIG_DIR",
    "MISE_DEBUG",
    "MISE_EXPERIMENTAL",
    "MISE_VERBOSE",
    "MISE_TRUSTED_CONFIG_PATHS",
    "__MISE_ORIG_PATH",
    "__MISE_DIFF",
    "__MISE_SESSION",
    "__MISE_WATCH",
    "__MISE_ZSH_PRECMD_RUN",
    "__MISE_ZSH_CHPWD_RAN",
}

-- A clean PATH that excludes the developer's globally-active mise tool installs
-- (notably ~/.local/share/mise/installs/nim/<global>/bin). Homebrew is included so
-- the `mise` and `gh` binaries remain resolvable. The sandbox nim is reached only
-- via `mise exec`, never via this PATH.
local SANITIZED_PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

local function build_env_prefix()
    -- Emit shell statements (not an `env` wrapper) so the prefix composes with
    -- compound commands containing shell builtins like `cd ... && mise ...`.
    -- Order: unset the leaking ambient vars, pin a sanitized PATH, then export the
    -- sandbox vars. Everything runs through `/bin/sh -c` (io.popen / os.execute).
    local parts = {}

    local unset_names = {}
    for _, name in ipairs(SCRUBBED_ENV_VARS) do
        -- Only scrub vars NOT explicitly set by the harness for the sandbox.
        if env_vars[name] == nil then
            table.insert(unset_names, name)
        end
    end
    if #unset_names > 0 then
        table.insert(parts, "unset " .. table.concat(unset_names, " ") .. ";")
    end

    -- PATH handling is OS-aware. On Windows (detected the same way exec() does,
    -- via package.config's path separator) the test runs under msys2, where the
    -- hardcoded Unix SANITIZED_PATH would wipe out /mingw64/bin (busted's lua5.1,
    -- coreutils), /usr/bin (msys coreutils), and the inherited mise.exe dir,
    -- breaking every mise/nim/awk/printf/command -v call. The global-tool-scrub
    -- hermeticity rationale doesn't apply on a clean CI runner, so we instead
    -- PREPEND the msys2 dirs to the INHERITED PATH so busted's lua5.1, msys
    -- coreutils, and the inherited mise.exe all resolve. On non-Windows we keep
    -- the hardcoded SANITIZED_PATH unchanged to preserve macOS/Linux hermeticity.
    if IS_WINDOWS then
        table.insert(parts, 'export PATH="/mingw64/bin:/usr/bin:$PATH";')
    else
        table.insert(parts, string.format("export PATH='%s';", SANITIZED_PATH))
    end

    for name, value in pairs(env_vars) do
        table.insert(parts, string.format("export %s='%s';", name, value))
    end

    return table.concat(parts, " ") .. " "
end

-- Sentinel used to recover the wrapped command's exit status from stdout.
-- LuaJIT's io.popen():close() returns only `true` regardless of the child exit
-- code (unlike PUC Lua 5.2+, which returns true/nil, "exit", code). Relying on
-- close() therefore reports EVERY command as a success, silently defeating the
-- success/failure assertions (e.g. the Error Handling test that expects a failed
-- install). We instead append `printf MARKER$?` after the command so the real
-- exit status is carried back in the captured output and parsed deterministically.
local EXIT_MARKER = "__VFOX_NIM_EXIT__"

-- Helper functions
local function exec(cmd)
    -- Wrap the (possibly compound) command in a group so $? reflects its exit
    -- status before the trailing 2>&1 redirect is applied.
    local full_cmd = build_env_prefix() .. "{ " .. cmd .. "; }; printf '" .. EXIT_MARKER .. '%d\' "$?"'
    -- run_posix captures stdout+stderr. On Windows it writes full_cmd to a temp
    -- script and runs `bash <script> 2>&1` (cmd.exe never sees the POSIX builtins
    -- or nested quotes); on Unix it runs `io.popen(full_cmd .. " 2>&1")` directly.
    -- The sentinel printf inside full_cmd carries the real exit status back in the
    -- captured output, parsed below (LuaJIT close() can't report it reliably).
    local result = run_posix(full_cmd, true)

    -- Recover the exit status from the sentinel, then strip it from the output.
    local code = result:match(EXIT_MARKER .. "(%d+)%s*$")
    result = result:gsub(EXIT_MARKER .. "%d*%s*$", "")
    local success = code == "0"

    -- Filter out DEBUG lines from mise output
    result = result:gsub("DEBUG[^\n]*\n", "")
    return result, success
end

local function exec_status(cmd)
    -- Compose the POSIX prefix + command (output discarded). run_posix runs it via
    -- os.execute and normalizes the Lua 5.1 (number) / 5.2+ (boolean) status into a
    -- boolean. On Windows it goes through the temp-script mechanism so the builtins
    -- (unset/export/command -v/test/etc.) are interpreted by bash, not cmd.exe.
    local full_cmd = build_env_prefix() .. cmd .. " >/dev/null 2>&1"
    local _, success = run_posix(full_cmd, false)
    return success
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
        raw_execute(
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
        exec("mise plugin uninstall nim 2>/dev/null || true")
        exec("mise plugin link nim '" .. PLUGIN_DIR .. "'")
        print("✓ Plugin linked from local path\n")
    end)

    -- Teardown runs once after all tests
    teardown(function()
        print("\n========================================")
        print("  Cleanup")
        print("========================================\n")

        print("→ Unlinking plugin...")
        exec("mise plugin uninstall nim 2>/dev/null || true")
        print("✓ Plugin unlinked")

        if MISE_TEST_DIR ~= "" and dir_exists(MISE_TEST_DIR) then
            print("→ Cleaning up temporary directory...")
            raw_execute("rm -rf '" .. MISE_TEST_DIR .. "'")
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
            -- Assert the resolved nim lives INSIDE the sandbox dir. Use a literal
            -- (plain) find because MISE_TEST_DIR contains '.' and '-' which are Lua
            -- pattern metacharacters; assert.matches would misinterpret them.
            assert.is_truthy(
                nim_path:find(MISE_TEST_DIR, 1, true),
                "nim not from sandbox mise directory (" .. MISE_TEST_DIR .. "): " .. nim_path
            )
        end)

        it("should have nimble available", function()
            local output, success = exec("mise exec nim@2.2.4 -- nimble --version 2>&1")
            assert.is_true(success, "nimble --version failed")
            assert.matches("nimble", output:lower())

            local nimble_path = exec("mise exec nim@2.2.4 -- which nimble 2>&1"):gsub("%s+$", "")
            -- Extract just the path (remove any shell output like "export -p")
            nimble_path = nimble_path:match("[^\n]*$")
            -- Literal (plain) find: MISE_TEST_DIR has Lua-pattern metacharacters.
            assert.is_truthy(
                nimble_path:find(MISE_TEST_DIR, 1, true),
                "nimble not from sandbox mise directory (" .. MISE_TEST_DIR .. "): " .. nimble_path
            )
        end)

        it("should compile and run a simple Nim program", function()
            local test_dir = make_temp_dir()
            raw_execute("mkdir -p '" .. test_dir .. "'")

            local f = io.open(test_dir .. "/hello.nim", "w")
            f:write('echo "Hello from Nim!"\n')
            f:close()

            local output, success = exec("cd '" .. test_dir .. "' && mise exec nim@2.2.4 -- nim c -r hello.nim 2>&1")
            raw_execute("rm -rf '" .. test_dir .. "'")

            assert.is_true(success, "Failed to compile simple Nim program")
            assert.matches("Hello from Nim!", output)
        end)
    end)

    describe("Environment Variables", function()
        it("should set NIMBLE_DIR to the per-version sandbox directory", function()
            local nimble_dir = exec("mise exec nim@2.2.4 -- sh -c 'echo $NIMBLE_DIR' 2>&1"):gsub("%s+$", "")
            nimble_dir = nimble_dir:match("[^\n]*$")

            -- env_keys.lua Priority 3 sets NIMBLE_DIR = <install>/nimble for the active
            -- version. With the ambient developer NIMBLE_DIR scrubbed by the harness, this
            -- must resolve to the sandbox-installed nim@2.2.4, isolating packages per
            -- version. Assert the FULL expected path so a regression to the global nim or
            -- a wrong version is caught.
            local nim_path = exec("mise where nim@2.2.4 2>&1"):gsub("%s+$", "")
            nim_path = nim_path:match("[^\n]*$")
            local expected = nim_path .. "/nimble"

            assert.are.equal(expected, nimble_dir, "NIMBLE_DIR should be the sandbox per-version nimble dir")
            -- Defensive: the resolved nim install itself must live inside the sandbox.
            assert.is_truthy(
                nim_path:find(MISE_TEST_DIR, 1, true),
                "nim install not inside sandbox (" .. MISE_TEST_DIR .. "): " .. nim_path
            )
        end)
    end)

    describe("Configuration Files", function()
        it("should support mise use command", function()
            local test_dir = make_temp_dir()
            raw_execute("mkdir -p '" .. test_dir .. "'")

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

            raw_execute("rm -rf '" .. test_dir .. "'")
            assert.is_true(has_config, "Neither mise.toml nor .tool-versions created with correct content")
        end)
    end)

    describe("Nimble Package Manager", function()
        it("should install a nimble package", function()
            local test_dir = make_temp_dir()
            raw_execute("mkdir -p '" .. test_dir .. "'")

            local output, success =
                exec("cd '" .. test_dir .. "' && echo 'y' | mise exec nim@2.2.4 -- nimble install -y argparse 2>&1")
            raw_execute("rm -rf '" .. test_dir .. "'")

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
            -- Match the exact user-facing message emitted by hooks/pre_install.lua
            -- (lowercased): "No pre-built binary available for version <v> on <os>/<arch>.
            -- User preference install_method='binary' prevents building from source."
            -- Use a literal (plain) find so the hyphen in "pre-built" is not treated as
            -- a Lua pattern metacharacter.
            assert.is_truthy(
                output:lower():find("no pre-built binary available for version 0.8.14", 1, true),
                "Error message should indicate no pre-built binary available. Output: " .. output
            )
        end)
    end)
end)
