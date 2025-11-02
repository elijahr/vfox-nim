std = "lua54"
globals = {
  -- Injected by mise
  "RUNTIME",
  "ctx",
  "PLUGIN",
  -- Mise Lua modules
  "http",
  "json",
  "file",
  "cmd",
  "env",
  "strings",
  "archiver",
}
ignore = {
  "212", -- Unused argument
  "542", -- Empty if branch
  "631", -- Line too long
}

-- Allow test files to mock global functions
files["spec/**/*.lua"] = {
  ignore = {
    "122", -- Setting read-only field (test mocking)
    "211", -- Unused variable
    "311", -- Variable never accessed
  },
}
