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

-- os.tmpname() on Windows returns a bare leaf like "\s5a2." rooted at the drive's
-- current dir, not an absolute path under TEMP. Normalize in two ordered steps:
-- (a) if the raw name is leading-backslash-rooted and TEMP is set, prepend %TEMP%
-- so the path is absolute and usable; (b) convert any remaining backslashes to
-- forward slashes so the path interpolates safely into single-quoted POSIX shell
-- commands (msys/git-bash) without backslash-escaping surprises. On Unix
-- os.tmpname() returns a "/"-rooted absolute path with no backslashes, so both
-- steps are no-ops.
local function tmpname()
    local name = os.tmpname()
    if name:sub(1, 1) == "\\" and os.getenv("TEMP") then
        name = os.getenv("TEMP") .. name
    end
    return name:gsub("\\", "/")
end

-- Ambient variables that leak the developer's GLOBALLY-active mise/nim toolchain
-- into the vfox sandbox and break hermeticity. mise's shell activation exports
-- these into every interactive shell (and thus into the busted process). The
-- plugin no longer sets NIMBLE_DIR (it lets nim use the shared ~/.nimble), but a
-- developer's inherited NIMBLE_DIR persists through activation unchanged, so
-- without scrubbing the activated vfox nim would still report the developer's
-- global NIMBLE_DIR (e.g. nim/2.2.10/nimble) and nimble would resolve packages
-- against that global dir instead of the clean sandbox default.
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
-- the `vfox` and `gh` binaries remain resolvable. The sandbox nim is reached only
-- via `vfox activate`, never via this PATH.
local SANITIZED_PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

local function build_env_prefix()
    -- Emit shell statements (not an `env` wrapper) so the prefix composes with
    -- compound commands containing shell builtins like `cd ... && nim ...` and
    -- `eval "$(vfox activate bash)"`. Everything runs through `/bin/sh -c`
    -- (io.popen / os.execute). Order: unset leaking ambient vars, pin a sanitized
    -- PATH, then export the sandbox vars (e.g. VFOX_HOME).
    local parts = {}

    local unset_names = {}
    for _, name in ipairs(SCRUBBED_ENV_VARS) do
        if env_vars[name] == nil then
            table.insert(unset_names, name)
        end
    end
    if #unset_names > 0 then
        table.insert(parts, "unset " .. table.concat(unset_names, " ") .. ";")
    end

    table.insert(parts, string.format("export PATH='%s';", SANITIZED_PATH))

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
-- install). We append `printf MARKER$?` after the command so the real exit status
-- is carried back in the captured output and parsed deterministically.
local EXIT_MARKER = "__VFOX_NIM_EXIT__"

-- Helper functions
local function exec(cmd)
    -- Wrap the (possibly compound) command in a group so $? reflects its exit
    -- status before the trailing 2>&1 redirect is applied.
    local full_cmd = build_env_prefix() .. "{ " .. cmd .. "; }; printf '" .. EXIT_MARKER .. '%d\' "$?"'
    -- On Windows, io.popen runs through cmd.exe which cannot interpret the POSIX
    -- shell builtins used above (unset/export/{ ...; }/printf). Re-wrap in `bash -c`
    -- so msys/git-bash interprets the command. On Unix this branch is skipped, so
    -- behavior is identical (the command already runs through /bin/sh).
    if package.config:sub(1, 1) == "\\" then
        full_cmd = "bash -c '" .. full_cmd:gsub("'", "'\\''") .. "'"
    end
    local handle = io.popen(full_cmd .. " 2>&1")
    local result = handle:read("*a")
    handle:close()

    -- Recover the exit status from the sentinel, then strip it from the output.
    local code = result:match(EXIT_MARKER .. "(%d+)%s*$")
    result = result:gsub(EXIT_MARKER .. "%d*%s*$", "")
    local success = code == "0"

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

-- Run a shell command with nim@2.2.4 activated via a project-local .tool-versions
-- file. This is vfox's reliable, hermetic activation path: inside a directory that
-- declares `nim 2.2.4`, `eval "$(vfox activate bash)"` materializes a per-project
-- .vfox/sdks/nim symlink and prepends its bin to PATH. (Global
-- `vfox use -g` activation does NOT take effect in a non-interactive `bash -c`
-- subshell — it needs a persistent shell hook session — so we never rely on it.)
-- The `inner` string runs after activation, with cwd at the project dir.
local function exec_with_nim(inner)
    local proj = tmpname()
    os.remove(proj)
    exec("mkdir -p '" .. proj .. "'")
    local f = io.open(proj .. "/.tool-versions", "w")
    f:write("nim 2.2.4\n")
    f:close()

    local script = 'cd "' .. proj .. '" && eval "$(vfox activate bash)" && ' .. inner
    local output, success = exec("bash -c '" .. script:gsub("'", "'\\''") .. "'")

    exec("rm -rf '" .. proj .. "'")
    return output, success, proj
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
    -- Durable, collision-free archive path shared by setup (create) and teardown (remove).
    -- mise-integration_spec.lua uses the same os.tmpname() pattern for its sandbox dir.
    -- NOTE: on a Windows runtime os.tmpname() may return a backslash path; the create site
    -- interpolates it into a single-quoted `git archive --output='...'` shell command under
    -- `shell: 'msys2 {0}'`, where a backslashed path is fragile and may need backslash->forward-slash
    -- normalization before interpolation. The integration tier is [CI-ONLY] on Windows (design
    -- §3.3); this caveat is validated by the first Windows integration CI run, not locally.
    local zip_path = tmpname() .. "-vfox-nim-test.zip"

    -- Sandbox vfox home so installs, plugins, and `vfox use -g` writes are fully
    -- contained and never touch the developer's real ~/.vfox. VFOX_HOME is vfox's
    -- documented home-directory override.
    local VFOX_TEST_HOME = tmpname():gsub("%.%w+$", "") .. ".vfox-nim-test-home"

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

        -- Create and activate the sandbox vfox home BEFORE any vfox invocation so
        -- every command below is hermetic.
        exec("mkdir -p '" .. VFOX_TEST_HOME .. "'")
        setenv("VFOX_HOME", VFOX_TEST_HOME)
        print("✓ Sandboxed vfox home: " .. VFOX_TEST_HOME)

        -- Set install method for faster tests
        setenv("VFOX_NIM_INSTALL_METHOD", "binary")
        print("✓ Using install_method='binary' for tests")

        -- Add the plugin using git archive. All vfox calls carry build_env_prefix()
        -- so they target the sandbox VFOX_HOME, not the developer's real ~/.vfox.
        print("\n→ Adding plugin for local testing...")
        exec("vfox remove -y nim 2>/dev/null || true")

        -- Create a zip archive of the current repository (zip_path is the describe-scoped local)
        local _, archive_ok =
            exec("cd '" .. PLUGIN_DIR .. "' && git archive --format=zip --output='" .. zip_path .. "' HEAD")
        assert(archive_ok, "Failed to create git archive")

        -- Add the plugin from the zip file
        local _, add_ok = exec("vfox add --source '" .. zip_path .. "' --alias nim 2>&1")
        assert(add_ok, "Failed to add plugin from zip")

        print("✓ Plugin added from local zip\n")
    end)

    -- Teardown runs once after all tests
    teardown(function()
        print("\n========================================")
        print("  Cleanup")
        print("========================================\n")

        print("→ Removing plugin...")
        exec("vfox remove -y nim 2>/dev/null || true")

        -- Remove the zip file if it exists (portable; removes exactly the file setup created)
        os.remove(zip_path)

        -- Remove the entire sandbox vfox home so nothing persists between runs.
        if VFOX_TEST_HOME ~= "" and dir_exists(VFOX_TEST_HOME) then
            exec("rm -rf '" .. VFOX_TEST_HOME .. "'")
        end

        print("✓ Plugin removed and sandbox home cleaned")
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
        it("should execute nim --version", function()
            -- nim writes its version banner to stderr; capture it.
            local output, success = exec_with_nim("nim --version 2>&1")
            assert.is_true(success, "nim --version failed: " .. output)
            assert.matches("Nim Compiler", output)
            -- Pin the exact version so a regression to the wrong nim is caught.
            assert.is_truthy(output:find("Version 2.2.4", 1, true), "nim is not version 2.2.4: " .. output)
        end)

        it("should have nimble available", function()
            local output, success = exec_with_nim("nimble --version 2>&1")
            assert.is_true(success, "nimble --version failed: " .. output)
            assert.matches("nimble", output:lower())
        end)

        it("should resolve nim from the activated vfox sdk, not a global toolchain", function()
            -- `which nim` must point at the per-project .vfox/sdks symlink created by
            -- activation, proving the sandbox toolchain (not a leaked global nim) is used.
            local output, success = exec_with_nim("command -v nim")
            assert.is_true(success, "command -v nim failed: " .. output)
            local nim_path = output:gsub("%s+$", ""):match("[^\n]*$")
            assert.is_truthy(
                nim_path:find("/.vfox/sdks/nim/bin/nim", 1, true),
                "nim not resolved from the activated vfox sdk: " .. nim_path
            )
        end)

        it("should compile and run a simple Nim program", function()
            -- Write the program into the activated project dir so it compiles there.
            local inner = "printf 'echo \"Hello from Nim!\"\\n' > hello.nim && nim c -r hello.nim 2>&1"
            local output, success = exec_with_nim(inner)
            assert.is_true(success, "Failed to compile simple Nim program: " .. output)
            assert.matches("Hello from Nim!", output)
        end)
    end)

    describe("Environment Variables", function()
        it("does not inject NIMBLE_DIR on activation (nim uses the shared ~/.nimble)", function()
            -- The plugin intentionally no longer sets NIMBLE_DIR (it previously set a
            -- per-version <sdk>/nimble path inherited from asdf-nim, which polluted the
            -- managed install dir and lost packages on reinstall). Leaving it unset means
            -- nim uses the shared ~/.nimble, a user-set NIMBLE_DIR persists, and
            -- project-local nimbledeps auto-detection still works.
            --
            -- The harness scrubs the developer's ambient NIMBLE_DIR for every command,
            -- so under `vfox activate` the ONLY thing that could set $NIMBLE_DIR is the
            -- plugin's env_keys. Assert it stays empty.
            local nimble_dir, success = exec_with_nim('echo "NIMBLE_DIR=[$NIMBLE_DIR]"')
            assert.is_true(success, "activation failed: " .. nimble_dir)
            nimble_dir = nimble_dir:gsub("%s+$", ""):match("NIMBLE_DIR=%[([^%]]*)%]")
            assert.are.equal(
                "",
                nimble_dir or "",
                "plugin must not inject NIMBLE_DIR on activation; got: " .. tostring(nimble_dir)
            )
        end)
    end)

    describe("Configuration Files", function()
        it("should activate the nim version declared in a .tool-versions file", function()
            -- Create a project dir that declares nim 2.2.4 via .tool-versions, then ask
            -- vfox which version it considers current there. This verifies real
            -- .tool-versions recognition rather than merely that the file was written.
            local test_dir = tmpname()
            os.remove(test_dir)
            exec("mkdir -p '" .. test_dir .. "'")
            local f = io.open(test_dir .. "/.tool-versions", "w")
            f:write("nim 2.2.4\n")
            f:close()

            local output, success =
                exec("bash -c 'cd \"" .. test_dir .. '" && eval "$(vfox activate bash)" && vfox current nim\'')

            exec("rm -rf '" .. test_dir .. "'")

            assert.is_true(success, "vfox current nim failed in .tool-versions dir: " .. output)
            assert.matches("2%.2%.4", output, "vfox did not report nim 2.2.4 as current for the .tool-versions dir")
        end)
    end)

    describe("Nimble Package Manager", function()
        it("should install a nimble package using the activated toolchain", function()
            -- Install argparse, then deterministically verify it is present via
            -- `nimble list --installed` (exit-code + name check) rather than scraping
            -- the non-deterministic install banner. Both run under the same activated
            -- nim@2.2.4 toolchain; the plugin does not inject NIMBLE_DIR, so nimble
            -- resolves its default (shared ~/.nimble) dir.
            local inner = "nimble install -y argparse 2>&1 && nimble list --installed 2>&1"
            local output, success = exec_with_nim(inner)

            assert.is_true(success, "nimble install/list failed: " .. output)
            assert.is_truthy(
                output:lower():find("argparse", 1, true),
                "argparse not reported as installed by nimble. Output: " .. output
            )
        end)
    end)

    describe("Uninstall and Reinstall", function()
        it("should uninstall and reinstall nim@2.2.4", function()
            local _, ok = exec("echo 'y' | vfox uninstall nim@2.2.4 2>&1")
            assert.is_true(ok, "uninstall command failed")
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
            exec("echo 'y' | vfox uninstall --yes nim@2.2.4 >/dev/null 2>&1 || true")

            setenv("VFOX_NIM_INSTALL_METHOD", "auto")
            local output, success = exec("vfox install --yes nim@2.2.4 2>&1")
            setenv("VFOX_NIM_INSTALL_METHOD", "binary")

            assert.is_true(success, "Installation with install_method='auto' failed: " .. output)

            local list_output = exec("vfox list nim 2>&1")
            assert.matches("2%.2%.4", list_output)
        end)

        it("should install with VFOX_NIM_INSTALL_METHOD='source'", function()
            -- Note: This test can be very slow as it builds from source
            exec("echo 'y' | vfox uninstall --yes nim@2.2.4 >/dev/null 2>&1 || true")

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
            -- Match the exact user-facing message emitted by hooks/pre_install.lua
            -- (lowercased): "No pre-built binary available for version <v> on <os>/<arch>.
            -- User preference install_method='binary' prevents building from source."
            -- Literal (plain) find so the hyphen in "pre-built" is not a Lua-pattern char.
            assert.is_truthy(
                output:lower():find("no pre-built binary available for version 0.8.14", 1, true),
                "Error message should indicate no pre-built binary available. Output: " .. output
            )
        end)
    end)
end)
