--- !!! DO NOT EDIT OR RENAME !!!
PLUGIN = {}

--- !!! MUST BE SET !!!
--- Plugin name
PLUGIN.name = "nim"
--- Plugin version
PLUGIN.version = "0.2.2"
--- Plugin repository
PLUGIN.homepage = "https://github.com/elijahr/vfox-nim"
--- Plugin license
PLUGIN.license = "MIT"
--- Plugin description
PLUGIN.description = "Nim compiler version manager with Windows support (vfox/mise tool plugin)"

--- !!! OPTIONAL !!!
PLUGIN.author = "elijahr"
PLUGIN.updateUrl = "https://github.com/elijahr/vfox-nim"
PLUGIN.manifestUrl = "https://github.com/elijahr/vfox-nim/releases/download/manifest/manifest.json"
PLUGIN.minRuntimeVersion = "0.2.0"

PLUGIN.legacyFilenames = {
    ".nim-version",
}

PLUGIN.notes = {
    "Supports Linux, macOS, and Windows",
    "Uses 4-level fallback: official binaries -> exact nightly -> generic nightly -> source",
    "Ported from production-tested asdf-nim logic",
    "Set GITHUB_TOKEN for higher API rate limits",
}
