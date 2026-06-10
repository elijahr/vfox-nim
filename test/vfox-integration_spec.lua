-- vfox integration tests - tests the plugin with actual vfox execution
-- Tests the vfox Tool Plugin hooks (Available, PreInstall, PostInstall, EnvKeys)
-- Run with: busted test/vfox-integration_spec.lua

-- Test environment setup
local IS_WINDOWS = package.config:sub(1, 1) == "\\"

-- Normalize a path for COMPARISON only. Two Windows-specific normalizations:
--   1. `\`->`/`: vfox/msys2 compose install paths with native backslashes while
--      the spec asserts forward-slash segments (.../bin/nim), yielding mixed
--      separators. Both forms are valid under msys2/mingw (real usage works), so
--      equality must collapse separators rather than treat the difference as a
--      failure.
--   2. strip trailing CR/whitespace: msys2 command output can carry a trailing
--      `\r` that the busted diff renders invisibly, making two "identical-looking"
--      strings compare unequal. Strip it before comparing.
-- No-op on Unix (no backslashes, no CR).
local function normalize_sep(path)
    return (path or ""):gsub("\\", "/"):gsub("[\r%s]+$", "")
end

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

local PLUGIN_DIR
if IS_WINDOWS then
    -- Native-Windows Lua's debug source is a backslash path; normalize separators
    -- so the dirname match and downstream interpolation into POSIX shell commands
    -- are consistent. (No-op on Unix.)
    local src = normalize_sep(debug.getinfo(1, "S").source:sub(2))
    PLUGIN_DIR = src:match("(.*/)") .. ".."
else
    local SCRIPT_DIR = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
    PLUGIN_DIR = SCRIPT_DIR .. ".."
end

-- Environment variable management
local env_vars = {}

local function setenv(name, value)
    env_vars[name] = value
end

-- Compute a clean, unique POSIX temp directory. os.tmpname() returns native
-- Windows names (e.g. \s5a2.) that are unusable as POSIX paths under msys2, so on
-- Windows we derive a clean directory via `mktemp -d` run through the bash wrapper.
-- On non-Windows we keep the os.tmpname() approach so macOS/Linux behavior is
-- byte-for-byte identical. The returned path is removed (it is used as a base name
-- onto which suffixes like ".zip" or "-home" are appended, mirroring the prior
-- os.tmpname() usage).
local function tmpname()
    if IS_WINDOWS then
        local dir = run_posix("mktemp -d", true)
        return (dir or ""):gsub("%s+$", "")
    end
    return os.tmpname()
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

    -- PATH handling is OS-aware. On Windows (detected via package.config's path
    -- separator) the test runs under msys2, where the hardcoded Unix SANITIZED_PATH
    -- would wipe out /mingw64/bin (busted's lua5.1, coreutils), /usr/bin (msys
    -- coreutils), and the inherited vfox.exe dir, breaking every vfox/nim/printf/
    -- command -v call. The global-tool-scrub hermeticity rationale doesn't apply on
    -- a clean CI runner, so we instead PREPEND the msys2 dirs to the INHERITED PATH
    -- so busted's lua5.1, msys coreutils, and the inherited vfox.exe all resolve. On
    -- non-Windows we keep the hardcoded SANITIZED_PATH unchanged to preserve
    -- macOS/Linux hermeticity, but PREPEND $HOME/.local/bin where jdx/mise-action
    -- installs the mise binary on Unix hosted runners (not in SANITIZED_PATH). vfox
    -- itself lives at /usr/bin or /opt/homebrew/bin (already covered), so this is
    -- harmless here but keeps both specs symmetric. ~/.local/bin holds mise, not
    -- the dev's global nim (~/.local/share/mise/installs), so hermeticity holds.
    -- HOME is expanded via os.getenv since SANITIZED_PATH is a literal Lua string.
    if IS_WINDOWS then
        table.insert(parts, 'export PATH="/mingw64/bin:/usr/bin:$PATH";')
    else
        local home = os.getenv("HOME") or ""
        table.insert(parts, string.format("export PATH='%s/.local/bin:%s';", home, SANITIZED_PATH))
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
-- install). We append `printf MARKER$?` after the command so the real exit status
-- is carried back in the captured output and parsed deterministically.
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

-- On Windows the busted Lua is native MinGW Lua whose io.open resolves Windows
-- paths, NOT the msys2 POSIX paths that `mktemp -d` returns (e.g. /tmp/tmp.XXX,
-- which msys maps to D:\a\_temp\msys64\tmp\...). Files created under those temp
-- dirs are therefore unreachable via native io.open, so existence/read checks must
-- route through bash (where the POSIX path is valid). On Unix the POSIX path IS a
-- native path, so we keep the direct io.open path for byte-for-byte parity.
local function file_exists(path)
    if IS_WINDOWS then
        return exec_status("test -f '" .. path .. "'")
    end
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

-- Write text to a file. On Windows, route through bash with printf so msys2 POSIX
-- paths resolve; on Unix use native io.open unchanged.
local function write_file(path, content)
    if IS_WINDOWS then
        -- printf %s avoids trailing-newline surprises; content is test-controlled.
        raw_execute("printf '%s' '" .. content:gsub("'", "'\\''") .. "' > '" .. path .. "'")
        return
    end
    local f = io.open(path, "w")
    f:write(content)
    f:close()
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
    -- On Windows tmpname() yields an msys2 POSIX path (mktemp -d); os.remove is a
    -- native call that cannot resolve it (harmless no-op) and mkdir -p is
    -- idempotent, so the dir from mktemp -d is reused. On Unix os.tmpname() created
    -- a file; os.remove clears it and mkdir -p recreates it as a dir, unchanged.
    local proj = tmpname()
    os.remove(proj)
    raw_execute("mkdir -p '" .. proj .. "'")
    -- write_file routes through bash on Windows (proj is an msys2 POSIX path native
    -- Lua io.open cannot resolve); native io.open on Unix.
    write_file(proj .. "/.tool-versions", "nim 2.2.4\n")

    local script = 'cd "' .. proj .. '" && eval "$(vfox activate bash)" && ' .. inner
    local output, success = exec("bash -c '" .. script:gsub("'", "'\\''") .. "'")

    raw_execute("rm -rf '" .. proj .. "'")
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
    -- tmpname() returns a clean POSIX base path on every platform: os.tmpname() on
    -- Unix, and `mktemp -d` (via the bash wrapper) on Windows where native
    -- os.tmpname() yields unusable backslash leaf names. The path interpolates
    -- safely into single-quoted `git archive --output='...'` shell commands.
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
        raw_execute("mkdir -p '" .. VFOX_TEST_HOME .. "'")
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

        -- Remove the zip file if it exists. Route through bash `rm -f` so the msys2
        -- POSIX zip_path resolves on Windows (native os.remove cannot); harmless on
        -- Unix where the path is native.
        raw_execute("rm -f '" .. zip_path .. "'")

        -- Remove the entire sandbox vfox home so nothing persists between runs.
        if VFOX_TEST_HOME ~= "" and dir_exists(VFOX_TEST_HOME) then
            raw_execute("rm -rf '" .. VFOX_TEST_HOME .. "'")
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
            -- normalize_sep collapses Windows backslashes and strips trailing CR/
            -- whitespace so the containment check is separator-agnostic (no-op on
            -- Unix). Apply it to the FULL output first (stripping the trailing
            -- newline) THEN take the last line, so a trailing "\n" does not yield an
            -- empty last line. Match the sdk bin path WITHOUT a binary extension:
            -- msys2 `command -v nim` reports the resolved path as `.../bin/nim`
            -- even though the file is nim.exe, and `/bin/nim` is a substring of
            -- both forms, so this works on Windows and Unix alike.
            local nim_path = normalize_sep(output):match("[^\n]*$")
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
            local nimble_dir_raw, success = exec_with_nim('echo "NIMBLE_DIR=[$NIMBLE_DIR]"')
            assert.is_true(success, "activation failed: " .. tostring(nimble_dir_raw))
            -- On Windows the captured value may be nil or carry a trailing CR while the
            -- plugin correctly injects nothing. Extract the bracketed value, then
            -- normalize (collapse separators, strip CR/whitespace): nil or
            -- empty-after-trim both mean "no NIMBLE_DIR injected" and PASS; a non-empty
            -- trimmed path still FAILS (real assertion, not a green mirage).
            local nimble_dir = normalize_sep((nimble_dir_raw or ""):match("NIMBLE_DIR=%[([^%]]*)%]") or "")
            assert.are.equal("", nimble_dir, "plugin must not inject NIMBLE_DIR on activation; got: " .. nimble_dir)
        end)
    end)

    describe("Configuration Files", function()
        it("should activate the nim version declared in a .tool-versions file", function()
            -- Create a project dir that declares nim 2.2.4 via .tool-versions, then ask
            -- vfox which version it considers current there. This verifies real
            -- .tool-versions recognition rather than merely that the file was written.
            local test_dir = tmpname()
            os.remove(test_dir)
            raw_execute("mkdir -p '" .. test_dir .. "'")
            -- write_file routes through bash on Windows (test_dir is an msys2 POSIX
            -- path from mktemp -d that native Lua io.open cannot resolve); native
            -- io.open on Unix.
            write_file(test_dir .. "/.tool-versions", "nim 2.2.4\n")

            local output, success =
                exec("bash -c 'cd \"" .. test_dir .. '" && eval "$(vfox activate bash)" && vfox current nim\'')

            raw_execute("rm -rf '" .. test_dir .. "'")

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
            -- Source compilation is not supported on Windows: Windows users get official
            -- prebuilt binaries, and `auto` correctly selects the binary path. Forcing a
            -- source build would compile Nim from C sources via MinGW/koch, which is out of
            -- scope. Mark pending so it shows as skipped (not passed) on Windows.
            if IS_WINDOWS then
                pending("source build not supported on Windows; binary is the supported install path")
                return
            end
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
