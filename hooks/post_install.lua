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
    local install_method = os.getenv("VFOX_NIM_INSTALL_METHOD") or "auto"

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

    -- Check if we need to restructure the archive
    -- mise: extracts to /path/to/install -> need to move nim-VERSION/* up
    -- vfox: extracts to /path/to/nim-VERSION -> files are already in place
    local path_basename = path:match("([^/]+)$")
    local needs_restructure = not path_basename:match("^nim%-")

    if needs_restructure then
        -- mise-style: Look for nim-* subdirectory and move contents up
        local find_cmd = 'find "' .. path .. '" -maxdepth 1 -type d -name "nim-*" 2>/dev/null | head -1'
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
            local success, _ = exec('"' .. path .. '\\finish.exe"')
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

    -- Test version
    local success, output = exec('"' .. nim_binary .. '" --version')
    if not success or not output:match("Nim Compiler") then
        error("Nim installation verification failed. Output: " .. (output or "none"))
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

    local function exec_or_error(cmd, error_msg, quiet)
        if not quiet then
            print("Running: " .. cmd)
        end
        -- Redirect stderr to suppress compiler warnings unless verbose mode
        local full_cmd = cmd
        if quiet and not os.getenv("MISE_VERBOSE") then
            full_cmd = cmd .. " 2>/dev/null"
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
        exec_or_error('cd "' .. install_path .. '" && .\\build_all.bat', "Failed to build Nim (build_all.bat)")
    else
        exec_or_error('cd "' .. install_path .. '" && sh build_all.sh', "Failed to build Nim (build_all.sh)")
    end

    -- Build koch if needed
    if not file_exists(install_path .. "/koch" .. nim_ext) then
        print("Building koch build tool...")
        local nim = install_path .. "/bin/nim" .. nim_ext
        exec_or_error(
            'cd "'
                .. install_path
                .. '" && "'
                .. nim
                .. '" c --skipParentCfg:on -d:release koch'
                .. (is_windows and ".nim" or ""),
            "Failed to build koch",
            true -- quiet mode
        )
    end

    -- Build nim with koch
    local koch = install_path .. "/koch" .. nim_ext
    if file_exists(koch) then
        print("Building Nim with koch...")
        exec_or_error(
            'cd "' .. install_path .. '" && "' .. koch .. '" boot -d:release',
            "Failed to boot Nim with koch",
            true
        )

        -- Build tools
        print("Building Nim tools...")
        if not file_exists(install_path .. "/bin/nimgrep" .. nim_ext) then
            exec_or_error(
                'cd "' .. install_path .. '" && "' .. koch .. '" tools -d:release',
                "Failed to build tools",
                true
            )
        end

        -- Build nimble if not present
        print("Building nimble package manager...")
        if not file_exists(install_path .. "/bin/nimble" .. nim_ext) then
            -- Try nimble build, but don't fail if it doesn't work (some versions don't have this)
            os.execute('cd "' .. install_path .. '" && "' .. koch .. '" nimble -d:release 2>/dev/null')
        end
    end

    print("Source build complete!")
end
