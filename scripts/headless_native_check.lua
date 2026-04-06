local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(source))
end

local root = repo_root()

vim.opt.runtimepath:append(root)
vim.cmd.source(vim.fs.joinpath(root, "plugin", "penguin.lua"))

local native = require("penguin.native")
local matcher = require("penguin.matcher")

assert(native.available)
assert(native.version() == 1)

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
