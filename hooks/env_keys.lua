-- hooks/env_keys.lua
-- Configures environment variables for Nim
-- Documentation: https://mise.jdx.dev/tool-plugin-development.html#envkeys-hook

function PLUGIN:EnvKeys(ctx)
    local mainPath = ctx.path
    local env_vars = {}

    -- Helper function to check if file/directory exists
    local function file_exists(filepath)
        local f = io.open(filepath, "r")
        if f ~= nil then
            io.close(f)
            return true
        end
        -- Try as directory
        local ok, _, code = os.rename(filepath, filepath)
        if ok or code == 13 then -- 13 is permission denied, but it exists
            return true
        end
        return false
    end

    -- Add bin to PATH
    table.insert(env_vars, {
        key = "PATH",
        value = mainPath .. "/bin",
    })

    -- Set NIMBLE_DIR with 3-level priority system (from asdf-nim)
    -- Priority 1: Respect existing NIMBLE_DIR environment variable
    local existing_nimble_dir = os.getenv("NIMBLE_DIR")
    if existing_nimble_dir and existing_nimble_dir ~= "" then
        -- User has already set NIMBLE_DIR, don't override it
        -- Return early with just PATH
        return env_vars
    end

    -- Priority 2: Check for project-local nimbledeps directory
    -- Get current working directory
    local cwd = os.getenv("PWD")
    if not cwd or cwd == "" then
        -- Fallback to getting cwd via command
        local handle = io.popen("pwd")
        cwd = handle:read("*a"):gsub("%s+$", "")
        handle:close()
    end

    if cwd and cwd ~= "" then
        local nimbledeps = cwd .. "/nimbledeps"
        if file_exists(nimbledeps) then
            -- Project-local nimbledeps exists, don't set NIMBLE_DIR
            -- Let Nim detect it naturally
            return env_vars
        end
    end

    -- Priority 3: Set per-version nimble directory
    -- This isolates packages per Nim version
    local nimble_dir = mainPath .. "/nimble"
    table.insert(env_vars, {
        key = "NIMBLE_DIR",
        value = nimble_dir,
    })

    return env_vars
end
