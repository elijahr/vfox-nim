-- hooks/env_keys.lua
-- Configures environment variables for Nim
-- Documentation: https://mise.jdx.dev/tool-plugin-development.html#envkeys-hook

function PLUGIN:EnvKeys(ctx)
    local mainPath = ctx.path
    local env_vars = {}

    -- Add bin to PATH
    table.insert(env_vars, {
        key = "PATH",
        value = mainPath .. "/bin",
    })

    -- NIMBLE_DIR is intentionally left UNSET (matching choosenim / standard
    -- nimble) so nim uses the shared ~/.nimble. The plugin previously set
    -- NIMBLE_DIR to a per-version {install}/nimble path (inherited from
    -- asdf-nim), which polluted the managed install dir and lost packages on
    -- version reinstall. Leaving it unset means:
    --   * a user-set NIMBLE_DIR persists (the plugin no longer clobbers it), and
    --   * nimble's project-local nimbledeps auto-detection still fires (it only
    --     triggers when NIMBLE_DIR is unset).
    -- Both behaviors are preserved for free by not emitting a NIMBLE_DIR entry.

    return env_vars
end
