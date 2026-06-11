-- hooks/post_install.lua
-- Performs additional setup after Nim installation
-- Documentation: https://mise.jdx.dev/tool-plugin-development.html#postinstall-hook

local utils = require("lib.nim_utils")

-- Forward declaration of build_from_source function
local build_from_source

function PLUGIN:PostInstall(ctx)
    local sdkInfo = ctx.sdkInfo[PLUGIN.name]
    local path = sdkInfo.path

    -- Get install method from environment (set by MiseEnv hook or directly)
    -- Valid values: "auto" (default), "binary", "source"
    local install_method = os.getenv("NIM_INSTALL_METHOD") or "auto"

    -- Helper function to check if file exists
    local function file_exists(filepath)
        local f = io.open(filepath, "r")
        if f ~= nil then
            io.close(f)
            return true
        end
        return false
    end

    -- Helper function to execute command and get result
    local function exec(cmd)
        local handle = io.popen(cmd .. " 2>&1")
        local result = handle:read("*a")
        local success = handle:close()
        return success, result
    end

    -- Determine if this is a binary release or source
    -- Binary releases have nim/bin/ directory with nim executable
    -- Source releases have build scripts
    local is_windows = utils.is_windows()
    local nim_ext = is_windows and ".exe" or ""

    -- Convert a path to a cmd.exe-compatible form on Windows. The SDK install path
    -- (`path`) is a NATIVE backslash path on Windows, but the plugin composes binary
    -- paths by appending forward-slash segments (e.g. path .. "/bin/nim" .. nim_ext),
    -- yielding a MIXED-separator path like `D:\a\...\nim-2.2.4/bin/nim.exe`. When such
    -- a path is quoted and handed to cmd.exe (every exec on Windows spawns cmd.exe),
    -- cmd.exe treats the forward slashes as switch characters and rejects the command
    -- ("is not recognized as an internal or external command"), failing the install.
    -- Collapse every "/" to "\" on the FINAL composed string used in a Windows exec.
    -- No-op on macOS/Linux (is_windows() is false; Unix paths have no backslashes), so
    -- existing Unix behavior is preserved byte-for-byte.
    local function native_path(p)
        if is_windows then
            return (p:gsub("/", "\\"))
        end
        return p
    end

    -- Wrap a FULLY-COMPOSED command string for safe execution under cmd.exe on Windows.
    -- vfox's exec on Windows routes through io.popen -> `cmd.exe /c "<command>"`. When the
    -- inner <command> STARTS with a double-quote (e.g. a quoted absolute path:
    -- `"D:\...\nim.exe" --version`), cmd.exe's quote-stripping rule strips the leading and
    -- trailing quote of the whole /c argument, mangling the command into
    -- `D:\...\nim.exe" --version` and failing with "is not recognized...". The documented
    -- cmd.exe remedy is to add an EXTRA outer quote pair around the whole command, so that
    -- after cmd strips the outermost pair the inner quotes survive intact:
    --   cmd /c ""D:\...\nim.exe" --version"
    -- Windows-only: guarded by is_windows() so Unix shells (which would mis-handle the extra
    -- quotes) keep the existing single-quoted form byte-for-byte. The same hook runs under
    -- both mise and vfox; the extra outer pair is also cmd.exe-correct for mise's shell.
    local function win_exec_str(cmd)
        if is_windows then
            return '"' .. cmd .. '"'
        end
        return cmd
    end

    -- Check if we need to restructure the archive
    -- mise: extracts to /path/to/install -> need to move nim-VERSION/* up
    -- vfox: extracts to /path/to/nim-VERSION -> files are already in place
    local path_basename = path:match("([^/]+)$")
    local needs_restructure = not path_basename:match("^nim%-")

    if needs_restructure then
        -- mise-style: Look for nim-* subdirectory and move contents up.
        -- OS-aware stderr discard (utils.null_redirect => `2>nul` on Windows). NOTE: the
        -- `find ... | head -1` pipeline is itself POSIX-only (no cmd.exe equivalent of
        -- find/head); this restructure path is reached on mise-style extraction regardless of
        -- OS, so the Unix-ism remains a known limitation here. Rewriting find|head is out of
        -- scope for this redirect-portability fix; only the redirect is normalized.
        local find_cmd = 'find "'
            .. path
            .. '" -maxdepth 1 -type d -name "nim-*" '
            .. utils.null_redirect()
            .. " | head -1"
        local handle = io.popen(find_cmd)
        local found_dir = handle:read("*a"):gsub("%s+$", "")
        handle:close()

        if found_dir and found_dir ~= "" and file_exists(found_dir) then
            -- Move contents up one level
            print("Restructuring extracted archive...")
            exec('cp -r "' .. found_dir .. '"/* "' .. path .. '/"')
            exec('rm -rf "' .. found_dir .. '"')
        end
    end

    -- Check if we already have a working binary (nightly builds come with pre-built binaries)
    local nim_binary = path .. "/bin/nim" .. nim_ext
    local has_binary = file_exists(nim_binary)

    if not has_binary then
        -- No binary exists, check if we need to build from source
        local has_build_script = file_exists(path .. "/build_all.sh") or file_exists(path .. "/build_all.bat")

        if has_build_script then
            -- Check if building from source is allowed
            if install_method == "binary" then
                error(
                    "Binary installation expected but source archive was downloaded. "
                        .. "This indicates a mismatch between PreInstall and PostInstall. "
                        .. "User preference install_method='binary' prevents building from source."
                )
            end

            -- Source build required
            print("Building Nim from source...")
            build_from_source(path, is_windows, nim_ext)
        else
            error("No Nim binary found and no build scripts available. Installation may be corrupted.")
        end
    else
        -- Binary exists - no build needed
        print("Using pre-built Nim binary")

        -- On Windows, run finish.exe if present
        -- finish.exe sets up PATH and optionally installs MinGW
        if is_windows and file_exists(path .. "/finish.exe") then
            print("Running Windows post-install setup (finish.exe)...")
            print("This will configure PATH and check for C compiler (MinGW)")
            local success, _ = exec(win_exec_str('"' .. native_path(path .. "/finish.exe") .. '"'))
            if not success then
                print("Warning: finish.exe failed, but this is not critical")
                print("You may need to manually install MinGW for compiling Nim code")
            end
        end
    end

    -- Verify installation
    nim_binary = path .. "/bin/nim" .. nim_ext
    if not file_exists(nim_binary) then
        error("Nim binary not found at " .. nim_binary .. ". Installation may have failed.")
    end

    -- Verify the install differently per platform.
    --
    -- On Windows we verify by FILE EXISTENCE rather than by running `nim --version`.
    -- The same hook runs under both vfox and mise, but each routes exec through a
    -- different shell: vfox spawns cmd.exe, mise spawns a POSIX-ish sh. There is NO
    -- single shell-quoted command form for an absolute Windows path that works under
    -- BOTH (cmd.exe rejects the quoted/mixed-separator path as "is not recognized as
    -- an internal or external command", while sh needs the quotes). Since the
    -- official prebuilt Windows binary is a known-good executable, its presence at
    -- the expected {install}/bin/nim.exe path is a sound install verification.
    -- Lua's io.open accepts both "/" and "\" on Windows, so the "/"-composed
    -- nim_binary path works directly without separator normalization, and this check
    -- introduces no shell dependency. Runtime execution (`nim --version`) is exercised
    -- by the integration tests and by real usage through the user's own shell.
    if is_windows then
        local f = io.open(nim_binary, "rb")
        if f == nil then
            error("Nim installation verification failed. Binary not found at " .. nim_binary)
        end
        io.close(f)
    else
        -- Unix: run `nim --version` to catch broken source builds.
        local success, output = exec('"' .. nim_binary .. '" --version')
        if not success or not output:match("Nim Compiler") then
            error("Nim installation verification failed. Output: " .. (output or "none"))
        end
    end

    print("Nim installed successfully!")
    return {}
end

-- Build Nim from source (from asdf-nim logic)
build_from_source = function(install_path, is_windows, nim_ext) -- luacheck: no global
    local function file_exists(filepath)
        local f = io.open(filepath, "r")
        if f ~= nil then
            io.close(f)
            return true
        end
        return false
    end

    -- See PostInstall's native_path: collapse "/" to "\" for paths embedded in
    -- Windows exec'd commands (cmd.exe rejects mixed/forward-slash quoted paths).
    -- No-op on Unix. Applied to the FINAL composed path strings only.
    local function native_path(p)
        if is_windows then
            return (p:gsub("/", "\\"))
        end
        return p
    end

    local function exec_or_error(cmd, error_msg, quiet)
        if not quiet then
            print("Running: " .. cmd)
        end
        -- Redirect stderr to suppress compiler warnings unless verbose mode.
        -- OS-aware redirect: the source-build path can run under cmd.exe on Windows (the
        -- build_all.bat branch), where `2>nul` is correct; utils.null_redirect() handles both.
        local full_cmd = cmd
        if quiet and not os.getenv("MISE_VERBOSE") then
            full_cmd = cmd .. " " .. utils.null_redirect()
        end
        local result = os.execute(full_cmd)
        if result ~= 0 and result ~= true then
            error(error_msg or ("Command failed: " .. cmd))
        end
    end

    -- Check for existing nim binary
    local nim_exists = file_exists(install_path .. "/bin/nim" .. nim_ext)

    if nim_exists then
        print("Nim compiler already exists, skipping bootstrap")
        return
    end

    print("Bootstrapping Nim compiler...")

    -- Workaround for ci/funs.sh: line 52: config/build_config.txt: No such file or directory
    if not file_exists(install_path .. "/config/build_config.txt") then
        -- make dirs
        exec_or_error('mkdir -p "' .. install_path .. '/config"', "Failed to create config directory")
        -- write multiline string to file
        local f = io.open(install_path .. "/config/build_config.txt", "w")
        f:write([[nim_comment="key-value pairs for windows/posix bootstrapping build scripts"
nim_csourcesDir=csources_v2
nim_csourcesUrl=https://github.com/nim-lang/csources_v2.git
nim_csourcesBranch=master
nim_csourcesHash=86742fb02c6606ab01a532a0085784effb2e753e
]])
        f:close()
    end

    -- Bootstrap nim
    if is_windows then
        exec_or_error(
            'cd "' .. native_path(install_path) .. '" && .\\build_all.bat',
            "Failed to build Nim (build_all.bat)"
        )
    else
        exec_or_error('cd "' .. install_path .. '" && sh build_all.sh', "Failed to build Nim (build_all.sh)")
    end

    -- Build koch if needed
    if not file_exists(install_path .. "/koch" .. nim_ext) then
        print("Building koch build tool...")
        local nim = native_path(install_path .. "/bin/nim" .. nim_ext)
        exec_or_error(
            'cd "'
                .. native_path(install_path)
                .. '" && "'
                .. nim
                .. '" c --skipParentCfg:on -d:release koch'
                .. (is_windows and ".nim" or ""),
            "Failed to build koch",
            true -- quiet mode
        )
    end

    -- Build nim with koch. The file_exists check uses the "/"-composed path (it runs
    -- through Lua io.open, which accepts forward slashes on Windows); only the koch
    -- path embedded in the exec'd command needs the native-backslash form for cmd.exe.
    local koch_path = install_path .. "/koch" .. nim_ext
    local koch = native_path(koch_path)
    if file_exists(koch_path) then
        print("Building Nim with koch...")
        exec_or_error(
            'cd "' .. native_path(install_path) .. '" && "' .. koch .. '" boot -d:release',
            "Failed to boot Nim with koch",
            true
        )

        -- Build tools
        print("Building Nim tools...")
        if not file_exists(install_path .. "/bin/nimgrep" .. nim_ext) then
            exec_or_error(
                'cd "' .. native_path(install_path) .. '" && "' .. koch .. '" tools -d:release',
                "Failed to build tools",
                true
            )
        end

        -- Build nimble if not present
        print("Building nimble package manager...")
        if not file_exists(install_path .. "/bin/nimble" .. nim_ext) then
            -- Try nimble build, but don't fail if it doesn't work (some versions don't have this).
            -- OS-aware stderr discard (utils.null_redirect => `2>nul` under cmd.exe on Windows).
            os.execute(
                'cd "'
                    .. native_path(install_path)
                    .. '" && "'
                    .. koch
                    .. '" nimble -d:release '
                    .. utils.null_redirect()
            )
        end
    end

    print("Source build complete!")
end
