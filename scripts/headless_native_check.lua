local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(source))
end

local root = repo_root()

vim.opt.runtimepath:append(root)
vim.cmd.source(vim.fs.joinpath(root, "plugin", "penguin.lua"))

local native = require("penguin.native")
local matcher = require("penguin.matcher")
local exact

assert(native.available)
assert(native.version() == 1)

exact = native.new_exact_matcher({
  "checkhealth",
  "write",
  "healthcheck",
})

assert(exact.handle ~= nil)
assert(exact.text_count == 3)
assert(exact.source_texts[2] == "write")

require("penguin").setup({
  native = {
    dev_probe = true,
  },
})

assert(matcher.backend_name() == "lua+native-probe")
assert(matcher.score("ckh", "checkhealth"))
assert(matcher.score("splbot", "vertical botright split"))
assert(not matcher.score("zz", "write"))

vim.cmd("qa!")
