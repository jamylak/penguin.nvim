local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(source))
end

local root = repo_root()

vim.opt.runtimepath:append(root)
vim.cmd.source(vim.fs.joinpath(root, "plugin", "penguin.lua"))

require("penguin").setup({})

local matcher = require("penguin.matcher")

assert(matcher.score("ckh", "checkhealth"))
assert(matcher.score("spl bot", "vertical botright split"))
assert(matcher.score("splbot", "vertical botright split"))
assert(matcher.score("pgo", "lua require('penguin').open()"))
assert(not matcher.score("zz", "write"))

vim.fn.histadd(":", "ls")
vim.fn.histadd(":", "checkhealth")
vim.fn.histadd(":", "vertical botright split")

require("penguin").open()

local session = require("penguin")._session

assert(session)
assert(#session.matches >= 3)
assert(session.matches[1].item.text == "vertical botright split")

require("penguin").close()

vim.cmd("qa!")
