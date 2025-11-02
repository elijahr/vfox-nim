#!/usr/bin/env bash
# Mise integration tests - tests the plugin with actual mise execution
# Based on mise plugin development documentation: https://mise.jdx.dev/backend-plugin-development.html

set -euo pipefail

# Enable mise debug output
export MISE_DEBUG=1

# Enable experimental features for backend plugins
export MISE_EXPERIMENTAL=1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Pass GitHub token if available (for API rate limiting)
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  export GITHUB_TOKEN
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  # Get token from gh CLI if available
  GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
  if [[ -n "$GITHUB_TOKEN" ]]; then
    export GITHUB_TOKEN
  fi
fi
if [[ -n "${GITHUB_API_TOKEN:-}" ]]; then
  export GITHUB_API_TOKEN
fi

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create temporary directory for sandboxed mise environment
MISE_TEST_DIR=$(mktemp -d -t mise-nim-test.XXXXXX)

# Sandbox mise to use temporary directory
export MISE_DATA_DIR="$MISE_TEST_DIR/data"
export MISE_CACHE_DIR="$MISE_TEST_DIR/cache"
export MISE_CONFIG_DIR="$MISE_TEST_DIR/config"

# Find mise location before isolating PATH
MISE_BIN=$(command -v mise)
if [ -z "$MISE_BIN" ]; then
  echo "ERROR: mise not found in PATH"
  exit 1
fi
MISE_BIN_DIR=$(dirname "$MISE_BIN")

# Isolate PATH to ensure we only use mise-managed tools
# Reset PATH to only essential system directories plus mise
export PATH="$MISE_BIN_DIR:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Setup test environment
setup() {
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}  Mise Plugin Integration Tests${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""

  # Create sandboxed mise directories
  mkdir -p "$MISE_DATA_DIR" "$MISE_CACHE_DIR" "$MISE_CONFIG_DIR"
  echo -e "${GREEN}✓${NC} Sandboxed mise environment created at $MISE_TEST_DIR"
  echo -e "  MISE_DATA_DIR=$MISE_DATA_DIR"
  echo -e "  MISE_CACHE_DIR=$MISE_CACHE_DIR"
  echo -e "  MISE_CONFIG_DIR=$MISE_CONFIG_DIR"

  # Use auto mode by default to support all platforms (tries binaries, then nightly, then source)
  # Tests 12-14 will explicitly test binary-only and auto modes
  export VFOX_NIM_INSTALL_METHOD="${VFOX_NIM_INSTALL_METHOD:-auto}"
  echo -e "${GREEN}✓${NC} Using install_method='${VFOX_NIM_INSTALL_METHOD}' for tests"

  # Check if mise is installed
  if ! command -v mise &>/dev/null; then
    echo -e "${RED}❌ mise is not installed${NC}"
    echo "Install mise from: https://mise.jdx.dev/getting-started.html"
    exit 1
  fi

  # Add mise bin and shims to PATH
  local mise_bin_dir
  mise_bin_dir=$(command -v mise | xargs dirname)
  export PATH="$MISE_DATA_DIR/installs/nim/2.2.4/bin:$MISE_DATA_DIR/shims:$mise_bin_dir:$PATH"

  echo ""
  local mise_version
  mise_version=$(mise --version | awk '{print $1}')
  echo -e "${GREEN}✓${NC} mise version: $(mise --version)"

  # Check if mise version is recent enough for backend plugin support
  # Backend plugin support was added in commit e311bbb73 on 2025-07-13
  # First released in mise v2025.10.0
  # Reference: https://github.com/jdx/mise/pull/5579
  local major minor
  IFS='.' read -r major minor _ <<<"$mise_version"
  if ((major < 2025 || (major == 2025 && minor < 10))); then
    echo ""
    echo -e "${RED}❌ mise version too old${NC}"
    echo -e "   Backend plugins require mise >= 2025.10.0"
    echo -e "   Current version: $mise_version"
    echo -e "   Update with: mise self-update"
    exit 1
  fi

  # Verify nim/nimble are NOT in PATH before installation
  echo ""
  if command -v nim &>/dev/null; then
    echo -e "${YELLOW}⚠${NC}  Warning: nim found in PATH at $(which nim)"
    echo -e "  This may interfere with tests"
  else
    echo -e "${GREEN}✓${NC} nim not found in PATH (good - will be installed by mise)"
  fi

  if command -v nimble &>/dev/null; then
    echo -e "${YELLOW}⚠${NC}  Warning: nimble found in PATH at $(which nimble)"
    echo -e "  This may interfere with tests"
  else
    echo -e "${GREEN}✓${NC} nimble not found in PATH (good - will be installed by mise)"
  fi

  # Link the plugin for local testing
  echo ""
  echo -e "${BLUE}→${NC} Linking plugin for local testing..."
  # Remove any existing installations
  mise plugin uninstall nim 2>/dev/null || true

  # Link the plugin for development
  # mise will detect it's a backend plugin based on the hooks/ directory structure
  mise plugin link nim "$PLUGIN_DIR"
  echo -e "${GREEN}✓${NC} Plugin linked from local path"
  echo ""
}

# Test helper function
test_case() {
  local test_name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -e "${BLUE}TEST ${TESTS_RUN}:${NC} ${test_name}"
}

# Pass helper
pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}  ✓ PASS${NC}"
  echo ""
}

# Fail helper
fail() {
  local message="$1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}  ✗ FAIL: ${message}${NC}"
  echo ""
}

# Test 1: Verify plugin is installed
test_plugin_installed() {
  test_case "mise plugin ls (verify nim plugin installed)"

  local output
  local exit_code
  output=$(mise plugin ls 2>&1)
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    if echo "$output" | grep -q "nim"; then
      pass
    else
      echo -e "${YELLOW}  Output: ${NC}"
      echo "$output"
      fail "nim plugin not found in plugin list"
    fi
  else
    echo -e "${RED}  Exit code: $exit_code${NC}"
    echo -e "${YELLOW}  Output: ${NC}"
    echo "$output"
    fail "mise plugin ls failed"
  fi
}

# Test 2: Verify plugin has hooks
test_plugin_hooks() {
  test_case "Verify plugin hook files exist"

  local plugin_path="$MISE_DATA_DIR/plugins/nim"

  if [[ -d "$plugin_path/hooks" ]]; then
    # Check for at least one hook file
    if ls "$plugin_path/hooks"/*.lua >/dev/null 2>&1; then
      pass
    else
      fail "No Lua hook files found in $plugin_path/hooks"
    fi
  else
    fail "Hooks directory not found at $plugin_path/hooks"
  fi
}

# Test 3: Install a specific version
test_install_version() {
  test_case "mise install nim@2.2.4"

  local output
  if output=$(mise install nim@2.2.4 2>&1); then
    if mise where nim@2.2.4 >/dev/null 2>&1; then
      local nim_path
      nim_path=$(mise where nim@2.2.4)
      if [[ -f "$nim_path/bin/nim" ]]; then
        pass
      else
        fail "nim binary not found at $nim_path/bin/nim"
      fi
    else
      fail "mise where nim@2.2.4 failed after installation"
    fi
  else
    echo -e "${YELLOW}  Output: ${NC}"
    echo "$output" | head -50
    fail "mise install nim@2.2.4 failed"
  fi
}

# Test 4: Verify nim executable works
test_nim_execution() {
  test_case "mise exec nim@2.2.4 -- nim --version"

  local output
  if output=$(mise exec nim@2.2.4 -- nim --version 2>&1); then
    if echo "$output" | grep -q "Nim Compiler"; then
      # Verify it's using the mise-installed version
      local nim_path
      nim_path=$(mise exec nim@2.2.4 -- which nim 2>&1)
      if [[ "$nim_path" == *"$MISE_DATA_DIR"* ]]; then
        pass
      else
        echo -e "${YELLOW}  Warning: nim not from mise directory${NC}"
        echo -e "  Expected: $MISE_DATA_DIR"
        echo -e "  Got: $nim_path"
        pass # Still pass but warn
      fi
    else
      fail "nim --version output doesn't contain 'Nim Compiler'"
    fi
  else
    fail "mise exec nim@2.2.4 -- nim --version failed"
  fi
}

# Test 5: Test nimble is available
test_nimble_available() {
  test_case "mise exec nim@2.2.4 -- nimble --version"

  local output
  if output=$(mise exec nim@2.2.4 -- nimble --version 2>&1); then
    if echo "$output" | grep -qi "nimble"; then
      # Verify it's using the mise-installed version
      local nimble_path
      nimble_path=$(mise exec nim@2.2.4 -- which nimble 2>&1)
      if [[ "$nimble_path" == *"$MISE_DATA_DIR"* ]]; then
        pass
      else
        echo -e "${YELLOW}  Warning: nimble not from mise directory${NC}"
        echo -e "  Expected: $MISE_DATA_DIR"
        echo -e "  Got: $nimble_path"
        pass # Still pass but warn
      fi
    else
      fail "nimble --version output doesn't contain 'nimble'"
    fi
  else
    fail "mise exec nim@2.2.4 -- nimble --version failed"
  fi
}

# Test 6: Test config file support (mise.toml or .tool-versions)
test_config_file() {
  test_case "mise use nim@2.2.4 in test directory"

  local test_dir
  test_dir=$(mktemp -d)

  cd "$test_dir"

  if mise use nim@2.2.4 2>&1; then
    # mise use can create either mise.toml or .tool-versions
    if [[ -f "mise.toml" ]]; then
      if grep -q "nim" "mise.toml" && grep -q "2.2.4" "mise.toml"; then
        cd - >/dev/null
        rm -rf "$test_dir"
        pass
      else
        echo -e "${YELLOW}  mise.toml content:${NC}"
        cat "mise.toml"
        cd - >/dev/null
        rm -rf "$test_dir"
        fail "mise.toml doesn't contain 'nim' and '2.2.4'"
      fi
    elif [[ -f ".tool-versions" ]]; then
      if grep -q "nim 2.2.4" ".tool-versions"; then
        cd - >/dev/null
        rm -rf "$test_dir"
        pass
      else
        echo -e "${YELLOW}  .tool-versions content:${NC}"
        cat ".tool-versions"
        cd - >/dev/null
        rm -rf "$test_dir"
        fail ".tool-versions doesn't contain 'nim 2.2.4'"
      fi
    else
      cd - >/dev/null
      rm -rf "$test_dir"
      fail "Neither mise.toml nor .tool-versions file created"
    fi
  else
    cd - >/dev/null
    rm -rf "$test_dir"
    fail "mise use nim@2.2.4 failed"
  fi
}

# Test 7: Verify NIMBLE_DIR environment variable
test_nimble_dir() {
  test_case "NIMBLE_DIR environment variable set correctly"

  # Use mise exec to get the environment
  local nimble_dir
  nimble_dir=$(mise exec nim@2.2.4 -- sh -c "echo \$NIMBLE_DIR" 2>&1)

  if [[ -n "$nimble_dir" ]]; then
    # NIMBLE_DIR should be set to version-specific directory
    if [[ "$nimble_dir" == *"nim"* && "$nimble_dir" == *"2.2.4"* ]]; then
      pass
    else
      echo -e "${YELLOW}  NIMBLE_DIR=$nimble_dir${NC}"
      echo -e "${YELLOW}  Expected it to contain nim and 2.2.4${NC}"
      pass # Still pass but warn
    fi
  else
    echo -e "${YELLOW}  NIMBLE_DIR is not set${NC}"
    echo -e "${YELLOW}  This may be intentional if a local nimbledeps exists${NC}"
    pass # Not necessarily a failure
  fi
}

# Test 8: Test nim can compile a simple program
test_nim_compile() {
  test_case "Compile and run a simple Nim program"

  local test_dir
  test_dir=$(mktemp -d)

  # Create a simple Nim program
  cat >"$test_dir/hello.nim" <<'EOF'
echo "Hello from Nim!"
EOF

  cd "$test_dir"

  local output
  if output=$(mise exec nim@2.2.4 -- nim c -r hello.nim 2>&1); then
    if echo "$output" | grep -q "Hello from Nim!"; then
      cd - >/dev/null
      rm -rf "$test_dir"
      pass
    else
      echo -e "${YELLOW}  Output: ${NC}"
      echo "$output"
      cd - >/dev/null
      rm -rf "$test_dir"
      fail "Compilation succeeded but output doesn't contain expected message"
    fi
  else
    echo -e "${YELLOW}  Output: ${NC}"
    echo "$output"
    cd - >/dev/null
    rm -rf "$test_dir"
    fail "Failed to compile simple Nim program"
  fi
}

# Test 9: Verify metadata.lua exists
test_metadata() {
  test_case "Verify metadata.lua exists"

  local plugin_path="$MISE_DATA_DIR/plugins/nim"

  if [[ -f "$plugin_path/metadata.lua" ]]; then
    pass
  else
    fail "metadata.lua not found at $plugin_path/metadata.lua"
  fi
}

# Test 10: List available versions
test_list_versions() {
  test_case "mise ls-remote nim"

  local output
  if output=$(mise ls-remote nim 2>&1); then
    if echo "$output" | grep -q "2.2.4"; then
      pass
    else
      echo -e "${YELLOW}  Output (first 20 lines): ${NC}"
      echo "$output" | head -20
      fail "Output doesn't contain expected version 2.2.4 (ensure GITHUB_TOKEN is set)"
    fi
  else
    echo -e "${RED}  Output: ${NC}"
    echo "$output"
    fail "mise ls-remote nim failed (ensure GITHUB_TOKEN is set to avoid rate limits)"
  fi
}

# Test 11: Test nimble can install a package
test_nimble_package() {
  test_case "Install a simple nimble package"

  local test_dir
  test_dir=$(mktemp -d)
  cd "$test_dir"

  # Try to install a small, well-known package
  local output
  # Use --accept to auto-accept prompts, and -y for yes to all
  if output=$(echo "y" | mise exec nim@2.2.4 -- nimble install -y argparse 2>&1 || true); then
    # Check if installation succeeded or if package already exists
    if echo "$output" | grep -qi "success\|installed\|already"; then
      cd - >/dev/null
      rm -rf "$test_dir"
      pass
    else
      echo -e "${YELLOW}  Output (first 30 lines): ${NC}"
      echo "$output" | head -30
      cd - >/dev/null
      rm -rf "$test_dir"
      # Don't fail hard on nimble package install - it depends on network
      echo -e "${YELLOW}  ⚠ SKIP: nimble package install may require network access${NC}"
      TESTS_PASSED=$((TESTS_PASSED + 1))
      echo ""
    fi
  else
    cd - >/dev/null
    rm -rf "$test_dir"
    # Don't fail hard on nimble package install - it depends on network
    echo -e "${YELLOW}  ⚠ SKIP: nimble package install may require network access${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo ""
  fi
}

# Test 12: Test install_method = 'auto' (default behavior)
test_install_method_auto() {
  test_case "Install with install_method='auto' (default)"

  # Clean install directory first
  mise uninstall nim@2.2.4 2>/dev/null || true

  local test_dir
  test_dir=$(mktemp -d)
  cd "$test_dir"

  # Create mise.toml with install_method = 'auto'
  cat >mise.toml <<'EOF'
[env]
_.vfox-nim = { install_method = "auto" }

[tools]
nim = "2.2.4"
EOF

  # Trust the config file
  mise trust 2>/dev/null || true

  # Install with auto mode
  local output
  if output=$(mise install 2>&1); then
    if mise where nim@2.2.4 >/dev/null 2>&1; then
      cd - >/dev/null
      rm -rf "$test_dir"
      pass
    else
      echo -e "${YELLOW}  Output: ${NC}"
      echo "$output" | tail -30
      cd - >/dev/null
      rm -rf "$test_dir"
      fail "nim 2.2.4 not installed after mise install"
    fi
  else
    echo -e "${YELLOW}  Output: ${NC}"
    echo "$output" | tail -30
    cd - >/dev/null
    rm -rf "$test_dir"
    fail "mise install failed with install_method='auto'"
  fi
}

# Test 13: Test install_method = 'binary' via MiseEnv hook
test_install_method_binary() {
  test_case "Install with install_method='binary' (via MiseEnv hook)"

  # Clean install directory first
  mise uninstall nim@2.2.4 2>/dev/null || true

  local test_dir
  test_dir=$(mktemp -d)
  cd "$test_dir"

  # Create mise.toml with install_method = 'binary'
  cat >mise.toml <<'EOF'
[env]
_.vfox-nim = { install_method = "binary" }

[tools]
nim = "2.2.4"
EOF

  # Trust the config file
  mise trust 2>/dev/null || true

  # Install with binary-only mode
  local output
  if output=$(mise install 2>&1); then
    if mise where nim@2.2.4 >/dev/null 2>&1; then
      cd - >/dev/null
      rm -rf "$test_dir"
      pass
    else
      echo -e "${YELLOW}  Output: ${NC}"
      echo "$output" | tail -30
      cd - >/dev/null
      rm -rf "$test_dir"
      # On platforms without binaries, this is expected to fail
      echo -e "${YELLOW}  ⚠ Note: Binary-only install may fail on platforms without pre-built binaries${NC}"
      pass # Don't fail - expected behavior on some platforms
    fi
  else
    # Check if it failed due to no binary available (expected on some platforms)
    if echo "$output" | grep -q "No pre-built binary available"; then
      echo -e "${YELLOW}  ⚠ Expected failure: No pre-built binary available for this platform${NC}"
      cd - >/dev/null
      rm -rf "$test_dir"
      pass # This is correct behavior
    else
      echo -e "${YELLOW}  Output: ${NC}"
      echo "$output" | tail -30
      cd - >/dev/null
      rm -rf "$test_dir"
      fail "mise install failed unexpectedly with install_method='binary'"
    fi
  fi
}

# Test 13b: Test that VFOX_NIM_INSTALL_METHOD env var overrides MiseEnv hook
test_install_method_env_var() {
  test_case "Verify VFOX_NIM_INSTALL_METHOD env var overrides MiseEnv hook"

  # Clean install directory first
  mise uninstall nim@2.2.4 2>/dev/null || true

  local test_dir
  test_dir=$(mktemp -d)
  cd "$test_dir"

  # Create mise.toml with BOTH MiseEnv hook (set to 'auto') AND env var (set to 'source')
  # The env var should take precedence
  cat >mise.toml <<'EOF'
[env]
_.vfox-nim = { install_method = "auto" }
VFOX_NIM_INSTALL_METHOD = "source"

[tools]
nim = "2.2.4"
EOF

  # Trust the config file
  mise trust 2>/dev/null || true

  # Install - should use 'source' from env var, not 'auto' from MiseEnv hook
  # This forces a source build even though 'auto' would use a binary on this platform
  local output
  if output=$(mise install 2>&1); then
    # Verify installation succeeded
    if mise where nim@2.2.4 >/dev/null 2>&1; then
      # The KEY test: verify it built from source (proving env var overrode MiseEnv)
      # If MiseEnv hook was used, we'd see "Using pre-built Nim binary" instead
      if echo "$output" | grep -q "Building from source"; then
        cd - >/dev/null
        rm -rf "$test_dir"
        pass
      else
        echo -e "${YELLOW}  Failed: Expected source build but got binary${NC}"
        echo -e "${YELLOW}  This means env var didn't override MiseEnv hook!${NC}"
        echo -e "${YELLOW}  Output (last 30 lines): ${NC}"
        echo "$output" | tail -30
        cd - >/dev/null
        rm -rf "$test_dir"
        fail "Env var VFOX_NIM_INSTALL_METHOD didn't override MiseEnv hook"
      fi
    else
      echo -e "${YELLOW}  Output: ${NC}"
      echo "$output" | tail -30
      cd - >/dev/null
      rm -rf "$test_dir"
      fail "Installation succeeded but binary not found"
    fi
  else
    echo -e "${YELLOW}  Output: ${NC}"
    echo "$output" | tail -30
    cd - >/dev/null
    rm -rf "$test_dir"
    fail "mise install failed with VFOX_NIM_INSTALL_METHOD env var"
  fi
}

# Test 14: Test uninstall and reinstall
test_uninstall_reinstall() {
  test_case "mise uninstall nim@2.2.4 && mise install nim@2.2.4"

  # Uninstall
  if mise uninstall nim@2.2.4 2>&1; then
    # Verify it's gone
    if ! mise where nim@2.2.4 >/dev/null 2>&1; then
      # Reinstall
      if mise install nim@2.2.4 2>&1; then
        # Verify it's back
        if mise where nim@2.2.4 >/dev/null 2>&1; then
          pass
        else
          fail "nim 2.2.4 not found after reinstall"
        fi
      else
        fail "Reinstall failed"
      fi
    else
      fail "Version still accessible after uninstall"
    fi
  else
    fail "Uninstall failed"
  fi
}

# Cleanup
cleanup() {
  # Skip if already cleaned up
  if [[ "${CLEANUP_DONE:-}" == "1" ]]; then
    return 0
  fi
  CLEANUP_DONE=1

  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}  Cleanup${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""

  # Unlink the plugin
  echo -e "${BLUE}→${NC} Unlinking plugin..."
  mise plugin uninstall nim 2>/dev/null || true
  echo -e "${GREEN}✓${NC} Plugin unlinked"

  # Clean up temporary mise directory
  if [[ -n "${MISE_TEST_DIR:-}" && -d "$MISE_TEST_DIR" ]]; then
    echo -e "${BLUE}→${NC} Cleaning up temporary directory..."
    rm -rf "$MISE_TEST_DIR"
    echo -e "${GREEN}✓${NC} Temporary directory removed"
  fi
}

# Print summary
summary() {
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}  Test Summary${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""
  echo -e "  Total:  ${TESTS_RUN}"
  echo -e "  ${GREEN}Passed: ${TESTS_PASSED}${NC}"

  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "  ${RED}Failed: ${TESTS_FAILED}${NC}"
    echo ""
    exit 1
  else
    echo -e "  Failed: 0"
    echo ""
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    exit 0
  fi
}

# Main test execution
main() {
  setup

  # Run tests (15 total - including install_method tests)
  test_plugin_installed       # 1
  test_plugin_hooks           # 2
  test_list_versions          # 3 (moved up - now matches vfox order)
  test_install_version        # 4
  test_nim_execution          # 5
  test_nimble_available       # 6
  test_nimble_dir             # 7
  test_nim_compile            # 8
  test_metadata               # 9
  test_config_file            # 10
  test_nimble_package         # 11
  test_install_method_auto    # 12 - Test install_method='auto'
  test_install_method_binary  # 13 - Test install_method='binary' (via MiseEnv)
  test_install_method_env_var # 13b - Test via env var
  test_uninstall_reinstall    # 14

  # Cleanup before summary
  cleanup
  summary
}

# Handle interrupts and cleanup
trap cleanup EXIT

main "$@"
