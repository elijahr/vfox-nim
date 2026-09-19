-- hooks/mise_env.lua
-- Provides configuration options for nim installation behavior
-- Documentation: https://mise.jdx.dev/env-plugin-development.html

function PLUGIN:MiseEnv(ctx)
    -- Get install_method from configuration (default: "auto")
    -- Valid values:
    --   "auto"   - Try binaries first, fall back to source (default)
    --   "binary" - Only use pre-built binaries, fail if unavailable
    --   "source" - Only build from source
    local install_method = "auto"
    local ok, val = pcall(function()
        return ctx.options.install_method
    end)
    if ok and val and val ~= "" then
        install_method = val
    end

    -- Validate install_method
    local valid_methods = { auto = true, binary = true, source = true }
    if not valid_methods[install_method] then
        error(string.format("Invalid install_method '%s'. Valid options: 'auto', 'binary', 'source'", install_method))
    end

    -- Return environment variable that PreInstall hook will read
    return {
        {
            key = "NIM_INSTALL_METHOD",
            value = install_method,
        },
    }
end
