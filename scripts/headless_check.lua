local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(source))
end

local root = repo_root()

vim.opt.runtimepath:append(root)
vim.cmd.source(vim.fs.joinpath(root, "plugin", "penguin.lua"))

require("penguin").setup({})

assert(vim.fn.maparg("<M-Space>", "n") ~= "")

local matcher = require("penguin.matcher")

assert(matcher.score("ckh", "checkhealth"))
assert(matcher.score("spl bot", "vertical botright split"))
assert(matcher.score("splbot", "vertical botright split"))
assert(matcher.score("pgo", "lua require('penguin').open()"))
assert(not matcher.score("zz", "write"))

vim.fn.histadd(":", "ls")
vim.fn.histadd(":", "checkhealth")
vim.fn.histadd(":", "vertical botright split")
vim.fn.histadd(":", "let g:penguin_complete = 21")
vim.fn.histadd(":", "let g:penguin_selected = 7")

require("penguin").open()

local session = require("penguin")._session

assert(session)
assert(#session.matches >= 3)
assert(session.matches[1].item.text == "let g:penguin_selected = 7")

session:complete_selection()

assert(session.query == "let g:penguin_selected = 7")
assert(vim.api.nvim_buf_get_lines(session.prompt_buf, 0, 1, false)[1] == "let g:penguin_selected = 7")

session:confirm()

assert(vim.g.penguin_selected == 7)

require("penguin").open()

session = require("penguin")._session

assert(session)
session:set_query("let g:penguin_direct = 13")
session:submit_query()

assert(vim.g.penguin_direct == 13)

require("penguin").close()

vim.cmd("qa!")
