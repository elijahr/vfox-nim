-- Tier-II install-logic tests: feed a realistic commits-API fixture through the
-- real date-offset + nightly-tag logic that the Tier-I empty mocks bypass.
require("spec.helpers")
local M = require("lib.nim_utils")
local fixture = require("spec.fixtures.nim_commit_2_2_4")

local EXPECTED_SHA = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"

describe("install logic (Tier II)", function()
    local orig_popen, orig_http_get, orig_json_decode, orig_url_exists
    local orig_getenv, orig_home, tmp_home

    before_each(function()
        -- Mock isolation: spec/install_method_spec.lua mutates _G.http.get / _G.json.decode
        -- in ITS before_each and NEVER restores them (its after_each only restores os.getenv).
        -- Depending on busted's file order, this spec can inherit those leaked stubs. Defend by
        -- (a) resetting the shared global mock state, and (b) re-establishing OUR OWN stubs fresh
        -- every test rather than trusting whatever http.get/json.decode currently point at.
        -- NOTE: helpers.reset_mocks() resets _G.PLUGIN/_G.RUNTIME/_G.ctx ONLY -- it does NOT
        -- restore http.get/json.decode to defaults. So we still re-stub them ourselves below
        -- (and each `it` that needs commit-info calls stub_commit_info() to set fresh stubs).
        local helpers = require("spec.helpers")
        helpers.reset_mocks()
        orig_popen = io.popen
        orig_http_get = _G.http.get
        orig_json_decode = _G.json.decode
        orig_url_exists = M.url_exists

        -- Cache hermeticity (MANDATORY, UPFRONT): get_version_commit_info reads/writes the REAL
        -- <HOME>/.cache/vfox-nim/version-commits.txt. A dev Mac that ran `mise run test` likely
        -- already has a real 2.2.4 cache line whose committer date differs from the fixture's
        -- fictitious 2025-03-17 -- a cache HIT would short-circuit the stubbed commits-API path
        -- and FAIL the date assertion on the very first run. So redirect HOME to a fresh empty
        -- tmp dir before every test. nim_utils resolves the cache dir via os.getenv("HOME"), so
        -- stubbing os.getenv for "HOME" is the robust redirect.
        --
        -- Uniqueness via os.tmpname(): the OS guarantees a unique path, with none of the
        -- collision risk of an unseeded math.random() (which would yield the same sequence on
        -- every interpreter start) or the float 1e9 literal. os.tmpname may create the file, so
        -- remove it and use its path as a fresh-directory base instead.
        orig_getenv = os.getenv
        orig_home = orig_getenv("HOME")
        local tmp_name = os.tmpname()
        os.remove(tmp_name)
        tmp_home = tmp_name .. "-vfox-nim-home"
        os.execute("mkdir -p '" .. tmp_home .. "/.cache/vfox-nim'")
        os.getenv = function(n)
            if n == "HOME" then
                return tmp_home
            end
            return orig_getenv(n)
        end

        -- Fresh default stubs (each test overrides as needed via stub_commit_info()):
        _G.http.get = function(_)
            return { status_code = 200, body = "[]" }, nil
        end
        _G.json.decode = function(_)
            return {}
        end
    end)

    after_each(function()
        io.popen = orig_popen
        _G.http.get = orig_http_get
        _G.json.decode = orig_json_decode
        M.url_exists = orig_url_exists
        os.getenv = orig_getenv
        assert.is_truthy(orig_home) -- sanity: original HOME captured
        if tmp_home then
            os.execute("rm -rf '" .. tmp_home .. "'")
        end
    end)

    -- helper: make git ls-remote return the fixture sha, and the commits API return the fixture.
    -- NOTE: get_version_commit_info also calls os.execute("mkdir -p <cache-dir>") -- that is
    -- os.execute, NOT io.popen, so this stub does NOT intercept it. The real mkdir still runs, but
    -- the redirected HOME points it at <tmp_home>/.cache/vfox-nim (created in before_each), so it
    -- never touches the developer's real $HOME.
    local function stub_commit_info()
        io.popen = function(cmd)
            local out
            if cmd:match("ls%-remote") then
                out = EXPECTED_SHA .. "\trefs/tags/v2.2.4^{}\n"
            else
                out = ""
            end
            return {
                read = function()
                    return out
                end,
                close = function()
                    return true
                end,
            }
        end
        _G.http.get = function(_)
            return { status_code = 200, body = "<commits-api-sentinel>" }, nil
        end
        _G.json.decode = function(_)
            return fixture
        end
    end

    it("get_platform_filename resolves macos/arm64", function()
        assert.are.equal("macosx_arm64.tar.xz", M.get_platform_filename("macos", "arm64"))
    end)

    it("version_to_branch slugs 2.2.4", function()
        assert.are.equal("version-2-2", M.version_to_branch("2.2.4"))
    end)

    it("get_version_commit_info parses committer.date", function()
        stub_commit_info()
        -- HOME is already redirected to a fresh empty tmp dir by before_each, so read_cache opens
        -- an absent <tmp_home>/.cache/vfox-nim/version-commits.txt => cache MISS, forcing the
        -- stubbed ls-remote + commits-API + json.decode(fixture) path.
        local hash, date = M.get_version_commit_info("2.2.4")
        assert.are.equal(EXPECTED_SHA, hash)
        assert.are.equal("2025-03-17", date)
    end)

    it("find_exact_nightly_url iterates offsets and builds the exact URL", function()
        stub_commit_info()
        local calls = {}
        M.url_exists = function(url)
            local d = url:match("download/(%d%d%d%d%-%d%d%-%d%d)")
            table.insert(calls, d)
            -- offset list is {1,0,2,-1,-2}: offset 1 => 2025-03-18 (reject), offset 0 => 2025-03-17 (accept)
            return d == "2025-03-17"
        end
        local url = M.find_exact_nightly_url("2.2.4", "macos", "arm64")
        assert.are.equal(
            "https://github.com/nim-lang/nightlies/releases/download/"
                .. "2025-03-17-version-2-2-"
                .. EXPECTED_SHA
                .. "/nim-2.2.4-macosx_arm64.tar.xz",
            url
        )
        -- green-mirage guard: prove the loop actually iterated past offset 1 before offset 0
        assert.are.equal("2025-03-18", calls[1])
        assert.are.equal("2025-03-17", calls[2])
    end)

    it("adjust_date offsets are correct across boundaries (timezone-independent)", function()
        assert.are.equal("2025-03-18", M.adjust_date("2025-03-17", 1))
        assert.are.equal("2025-02-28", M.adjust_date("2025-03-01", -1))
        assert.are.equal("2026-01-01", M.adjust_date("2025-12-31", 1)) -- year boundary
        assert.are.equal("2024-02-29", M.adjust_date("2024-02-28", 1)) -- leap
        assert.are.equal("", M.adjust_date("garbage", 1)) -- malformed
    end)
end)

-- Directly exercise the rewritten OS-detection functions (is_macos/is_windows) in
-- hooks/lib/nim_utils.lua. These functions branch on _G.RUNTIME.osType first (the value
-- vfox/mise injects inside a hook), then fall back to the OS env var and `uname` for
-- standalone/test contexts. The Tier-II install-logic tests above never assert these
-- functions, so without this block the OS-detection rewrite is a green-mirage gap.
describe("OS detection (is_macos/is_windows)", function()
    local utils = require("lib.nim_utils")
    local saved_runtime, orig_getenv, orig_popen

    before_each(function()
        -- Capture exactly the globals this block mutates so the after_each can restore them
        -- without disturbing the install-logic before_each/after_each above.
        saved_runtime = _G.RUNTIME
        orig_getenv = os.getenv
        orig_popen = io.popen
    end)

    after_each(function()
        _G.RUNTIME = saved_runtime
        os.getenv = orig_getenv
        io.popen = orig_popen
    end)

    -- RUNTIME.osType-first branch: when vfox/mise injects osType, neither the OS env var nor
    -- `uname` is consulted. Assert both predicates for each osType so a wrong match() (e.g.
    -- is_macos matching "windows") is caught by the cross-predicate equalities.

    it("RUNTIME.osType=Darwin => macos true, windows false", function()
        _G.RUNTIME = { osType = "Darwin" }
        assert.equals(true, utils.is_macos())
        assert.equals(false, utils.is_windows())
    end)

    it("RUNTIME.osType=Windows_NT => windows true, macos false", function()
        _G.RUNTIME = { osType = "Windows_NT" }
        assert.equals(true, utils.is_windows())
        assert.equals(false, utils.is_macos())
    end)

    it("RUNTIME.osType=Linux => both false", function()
        _G.RUNTIME = { osType = "Linux" }
        assert.equals(false, utils.is_macos())
        assert.equals(false, utils.is_windows())
    end)

    -- Env-fallback + nil-guard branch: with RUNTIME nil, is_windows() consults os.getenv("OS")
    -- (Windows_NT on every Windows), and is_macos() shells out to `uname`. Both must guard the
    -- nil RUNTIME without erroring.

    it("RUNTIME nil + OS=Windows_NT env => is_windows true", function()
        _G.RUNTIME = nil
        os.getenv = function(name)
            if name == "OS" then
                return "Windows_NT"
            end
            return orig_getenv(name)
        end
        assert.equals(true, utils.is_windows())
    end)

    it("RUNTIME nil + OS unset + uname=Darwin => is_macos true", function()
        _G.RUNTIME = nil
        os.getenv = function(name)
            if name == "OS" then
                return nil
            end
            return orig_getenv(name)
        end
        io.popen = function(cmd)
            assert.equals("uname 2>/dev/null", cmd)
            return {
                read = function()
                    return "Darwin\n"
                end,
                close = function()
                    return true
                end,
            }
        end
        assert.equals(true, utils.is_macos())
    end)
end)

-- Regression: url_exists must NOT forward the GitHub Authorization header to
-- release-download / nim-lang.org hosts. Those URLs 302-redirect to a presigned
-- asset host that REJECTS a forwarded Authorization header with HTTP 401, so when
-- GITHUB_TOKEN is set (CI + both test harnesses always set it) url_exists wrongly
-- returns false and find_exact_nightly_url exhausts every date offset, surfacing as
-- "No pre-built binary available". The auth header is only legitimate (and only
-- needed for the 60/hr rate limit) on api.github.com.
describe("url_exists auth-header scoping", function()
    local utils = require("lib.nim_utils")
    local orig_head, orig_getenv, captured_headers

    before_each(function()
        orig_head = _G.http.head
        orig_getenv = os.getenv
        captured_headers = nil
        -- Capture exactly the headers url_exists passes to http.head, and return a
        -- 200 so url_exists's own return value is governed solely by the header logic.
        _G.http.head = function(opts)
            captured_headers = opts.headers
            return { status_code = 200 }, nil
        end
        -- Token present: this is the precise condition that triggered the bug.
        os.getenv = function(name)
            if name == "GITHUB_TOKEN" then
                return "ghp_TESTTOKEN1234567890"
            end
            return orig_getenv(name)
        end
    end)

    after_each(function()
        _G.http.head = orig_head
        os.getenv = orig_getenv
    end)

    it("sends NO Authorization header to a releases/download URL (with token set)", function()
        local result = utils.url_exists(
            "https://github.com/nim-lang/nightlies/releases/download/"
                .. "2025-03-17-version-2-2-a1b2c3d4/nim-2.2.4-macosx_arm64.tar.xz"
        )
        assert.equals(true, result)
        -- Exact: the header table for a non-api host must have NO Authorization field.
        assert.is_nil(captured_headers["Authorization"])
    end)

    it("sends NO Authorization header to a nim-lang.org URL (with token set)", function()
        local result = utils.url_exists("https://nim-lang.org/download/nim-2.2.4-linux_x64.tar.xz")
        assert.equals(true, result)
        assert.is_nil(captured_headers["Authorization"])
    end)

    it("DOES send the Authorization header to api.github.com (with token set)", function()
        local result = utils.url_exists("https://api.github.com/repos/nim-lang/Nim/commits/a1b2c3d4")
        assert.equals(true, result)
        -- Exact: api calls still authenticate with the token form "token <TOKEN>".
        assert.are.same({ ["Authorization"] = "token ghp_TESTTOKEN1234567890" }, captured_headers)
    end)
end)
