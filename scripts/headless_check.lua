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

assert(matcher.backend_name() == "lua")

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
vim.fn.histadd(":", "set numberwidth=5")

require("penguin").open()

local session = require("penguin")._session

assert(session)
assert(#session.matches >= 3)
session:set_query("penguin sel")

assert(session.matches[1].item.text == "let g:penguin_selected = 7")

session:complete_selection()

assert(session.query == "let g:penguin_selected = 7")
assert(vim.api.nvim_buf_get_lines(session.prompt_buf, 0, 1, false)[1] == ": let g:penguin_selected = 7")

session:confirm()

vim.wait(1000, function()
  return vim.g.penguin_selected == 7
end)
assert(vim.g.penguin_selected == 7)

require("penguin").open()

session = require("penguin")._session

assert(session)
session:set_query("let g:penguin_direct = 13")
session:submit_query()

vim.wait(1000, function()
  return vim.g.penguin_direct == 13
end)
assert(vim.g.penguin_direct == 13)

require("penguin").open()

session = require("penguin")._session

assert(session)
session:set_query("set nu")

local saw_history = false
local saw_completion = false

for _, match in ipairs(session.matches) do
  if match.item.text == "set numberwidth=5" and match.item.source == "history" then
    saw_history = true
  end

  if match.item.text == "set number" and match.item.source == "completion" then
    saw_completion = true
  end
end

assert(saw_history)
assert(saw_completion)

session:set_query("let g:penguin word")
session:delete_word_backward()
assert(session.query == "let g:penguin")
assert(vim.api.nvim_buf_get_lines(session.prompt_buf, 0, 1, false)[1] == ": let g:penguin")

vim.api.nvim_buf_set_lines(session.prompt_buf, 0, -1, false, { ": ls" })
vim.api.nvim_exec_autocmds("TextChangedI", {
  buffer = session.prompt_buf,
})
assert(session.query == "ls")
assert(session.matches[1].item.text == "ls")

vim.api.nvim_buf_set_lines(session.prompt_buf, 0, -1, false, { ": " })
vim.api.nvim_exec_autocmds("TextChangedI", {
  buffer = session.prompt_buf,
})
assert(session.query == "")
assert(#session.matches >= 1)

assert(vim.fn.maparg("<C-n>", "i", false, true).lhs == "<C-N>")
assert(vim.fn.maparg("<C-p>", "i", false, true).lhs == "<C-P>")
assert(vim.fn.maparg("<C-w>", "i", false, true).lhs == "<C-W>")

require("penguin").close()

vim.cmd("qa!")
