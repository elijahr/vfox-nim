-- metadata.lua
-- Plugin metadata and configuration
-- Documentation: https://mise.jdx.dev/tool-plugin-development.html#metadata-lua

PLUGIN = {
    -- Required: Tool name (lowercase, no spaces)
    name = "nim",

    -- Required: Plugin version (not the tool version)
    version = "0.1.0",

    -- Required: Brief description of the tool
    description = "Nim compiler version manager with Windows support (vfox/mise tool plugin)",

    -- Required: Plugin author/maintainer
    author = "elijahr",

    -- Optional: Repository URL for plugin updates
    updateUrl = "https://github.com/elijahr/vfox-nim",

    -- Optional: Minimum mise runtime version required
    minRuntimeVersion = "0.2.0",

    -- Optional: Legacy version files this plugin can parse
    legacyFilenames = {
        ".nim-version",
    },

    -- Optional: Additional notes
    notes = {
        "Supports Linux, macOS, and Windows",
        "Uses 4-level fallback: official binaries -> exact nightly -> generic nightly -> source",
        "Ported from production-tested asdf-nim logic",
        "Set GITHUB_TOKEN for higher API rate limits",
    },
}
