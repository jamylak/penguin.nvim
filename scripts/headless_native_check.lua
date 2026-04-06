local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(source))
end

local root = repo_root()

vim.opt.runtimepath:append(root)

local native = require("penguin.native")

assert(native.available)
assert(native.version() == 1)

vim.cmd("qa!")
