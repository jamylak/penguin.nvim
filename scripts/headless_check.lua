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
local ui = require("penguin.ui")

local function extmarks_with_detail(buffer, namespace, detail_key, detail_value)
  local matches = {}

  for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {
    details = true,
  })) do
    local details = extmark[4] or {}

    if details[detail_key] == detail_value then
      matches[#matches + 1] = extmark
    end
  end

  return matches
end

local function visible_line_range(window)
  return vim.api.nvim_win_call(window, function()
    return {
      bottom = vim.fn.line("w$"),
      top = vim.fn.line("w0"),
    }
  end)
end

assert(matcher.backend_name() == "native-fuzzy-query")

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
local match_extmarks = extmarks_with_detail(session.results_buf, ui.namespace, "hl_group", "PenguinMatch")
local selection_extmarks = extmarks_with_detail(
  session.results_buf,
  ui.namespace,
  "line_hl_group",
  "Visual"
)
assert(#match_extmarks == 2)
assert(#selection_extmarks == 1)
assert(match_extmarks[1][4].priority > selection_extmarks[1][4].priority)

session:complete_selection()

assert(session.query == "let g:penguin_selected = 7")
assert(vim.api.nvim_buf_get_lines(session.prompt_buf, 0, 1, false)[1] == ": let g:penguin_selected = 7")

session:confirm()

vim.wait(1000, function()
  return vim.g.penguin_selected == 7
end)
assert(vim.g.penguin_selected == 7)
assert(vim.fn.histget(":", -1) == "let g:penguin_selected = 7")

require("penguin").open()

session = require("penguin")._session

assert(session)
session:set_query("let g:penguin_direct = 13")
session:submit_query()

vim.wait(1000, function()
  return vim.g.penguin_direct == 13
end)
assert(vim.g.penguin_direct == 13)
assert(vim.fn.histget(":", -1) == "let g:penguin_direct = 13")

vim.cmd("enew!")
vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn["repeat"]({ "penguin" }, 40))

require("penguin").open()

session = require("penguin")._session

assert(session)
session:set_query("33")
session:confirm()

vim.wait(1000, function()
  return vim.api.nvim_win_get_cursor(0)[1] == 33
end)
assert(vim.api.nvim_win_get_cursor(0)[1] == 33)
assert(vim.fn.histget(":", -1) == "33")

vim.cmd("enew!")
vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn["repeat"]({ "penguin" }, 40))
vim.fn.histadd(":", "30verbose set number")

require("penguin").open()

session = require("penguin")._session

assert(session)
session:set_query("30")
assert(session.matches[1].item.text == "30verbose set number")
session:confirm()

vim.wait(1000, function()
  return vim.api.nvim_win_get_cursor(0)[1] == 30
end)
assert(vim.api.nvim_win_get_cursor(0)[1] == 30)
assert(vim.fn.histget(":", -1) == "30")

require("penguin").open()

session = require("penguin")._session

assert(session)
session:set_query("set nu")
vim.wait(1000, function()
  for _, match in ipairs(session.matches) do
    if match.item.text == "set number" and match.item.source == "completion" then
      return true
    end
  end

  return false
end)

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
assert(vim.fn.maparg("<Tab>", "i", false, true).lhs == "<Tab>")

require("penguin").close()

require("penguin").setup({
  ui = {
    match_highlights = false,
  },
})

require("penguin").open()

session = require("penguin")._session

assert(session)
session:set_query("penguin sel")
assert(#vim.api.nvim_buf_get_extmarks(session.results_buf, ui.namespace, 0, -1, {}) == 1)
require("penguin").close()

require("penguin").setup({})
require("penguin").open()

session = require("penguin")._session

assert(session)
session.entries = {}
session.native_history_matcher = {
  handle = nil,
  text_count = 0,
}
session:set_query("l")

assert(#session.matches >= 1)
assert(session.matches[1].item.source == "completion")
assert(vim.api.nvim_buf_get_lines(session.results_buf, 0, 1, false)[1] ~= "  no command history yet")

require("penguin").close()

for index = 1, 160 do
  vim.fn.histadd(":", ("PenguinBenchCommand%03d"):format(index))
end

require("penguin").setup({
  ui = {
    max_results = 100,
  },
})

require("penguin").open()

session = require("penguin")._session

assert(session)
assert(#session.matches == 100)
assert(#vim.api.nvim_buf_get_lines(session.results_buf, 0, -1, false) == 100)
assert(vim.api.nvim_win_get_height(session.results_win) < #session.matches)

local initial_line = vim.api.nvim_buf_get_lines(session.results_buf, 0, 1, false)[1]
local initial_view = visible_line_range(session.results_win)
local jump = vim.api.nvim_win_get_height(session.results_win) + 5

assert(initial_line:sub(1, 2) == "  ")
assert(initial_view.top == 1)
assert(initial_view.bottom < #session.matches)

session:move_selection(jump)

local selection_extmarks_large = extmarks_with_detail(
  session.results_buf,
  ui.namespace,
  "line_hl_group",
  "Visual"
)
local scrolled_view = visible_line_range(session.results_win)

assert(#selection_extmarks_large == 1)
assert(selection_extmarks_large[1][2] == jump)
assert(selection_extmarks_large[1][4].virt_text[1][1] == ">")
assert(vim.api.nvim_buf_get_lines(session.results_buf, jump, jump + 1, false)[1]:sub(1, 2) == "  ")
assert(vim.api.nvim_buf_get_lines(session.results_buf, 0, 1, false)[1]:sub(1, 2) == "  ")
assert(scrolled_view.top > initial_view.top)
assert(session.selection >= scrolled_view.top)
assert(session.selection <= scrolled_view.bottom)

require("penguin").close()

local completion = require("penguin.completion")
local original_complete = completion._complete
local completion_calls = {}

completion._complete = function(query, kind)
  completion_calls[#completion_calls + 1] = {
    kind = kind,
    query = query,
  }

  if kind == "command" and query == "check" then
    return {
      "checkhealth",
    }
  end

  if kind == "cmdline" and query == "checkhealth " then
    return {
      "vim.deprecated",
      "vim.health",
      "vim.lsp",
      "vim.provider",
    }
  end

  return {}
end

require("penguin").setup({
  completion = {
    debounce_ms = 10,
    command_strategies = {
      checkhealth = "prefix_cached_deferred",
      slowcmd = "deferred",
    },
  },
})

require("penguin").open()

session = require("penguin")._session

assert(session)
session:set_query("check")
assert(#completion_calls == 1)
assert(completion_calls[1].kind == "command")
assert(completion_calls[1].query == "check")

completion_calls = {}
session:set_query("slowcmd a")
session:set_query("slowcmd ab")
assert(#completion_calls == 0)

vim.wait(1000, function()
  return #completion_calls == 1
end)

assert(#completion_calls == 1)
assert(completion_calls[1].kind == "cmdline")
assert(completion_calls[1].query == "slowcmd ab")

completion_calls = {}
session:set_query("checkhealth ")
session:set_query("checkhealth v")
session:set_query("checkhealth vi")
assert(#completion_calls == 0)

vim.wait(1000, function()
  return #completion_calls == 1
end)

assert(#completion_calls == 1)
assert(completion_calls[1].kind == "cmdline")
assert(completion_calls[1].query == "checkhealth ")

local saw_deferred_completion = false

for _, match in ipairs(session.matches) do
  if match.item.text == "checkhealth vim.health" and match.item.source == "completion" then
    saw_deferred_completion = true
    break
  end
end

assert(saw_deferred_completion)

session:set_query("checkhealth vim")
vim.wait(50)
assert(#completion_calls == 1)

completion_calls = {}
session:set_query("che ")
session:set_query("che v")
session:set_query("che vi")
-- `:che` is a unique abbreviation for `:checkhealth`, so it should inherit the
-- same deferred strategy immediately instead of running slow cmdline completion
-- again for each extra typed suffix.
assert(#completion_calls == 0)

vim.wait(1000, function()
  return #completion_calls == 1
end)

assert(#completion_calls == 1)
assert(completion_calls[1].kind == "cmdline")
assert(completion_calls[1].query == "che ")

session:set_query("che vim")
vim.wait(50)
-- Once the abbreviated command prefix has been fetched/cached, more typing on
-- the same command should keep reusing that result.
assert(#completion_calls == 1)

completion._complete = original_complete
require("penguin").close()

local path_root = vim.fn.tempname()
local path_child = vim.fs.joinpath(path_root, "penguinpathchild")
local path_items

assert(vim.fn.mkdir(path_child, "p") == 1)

require("penguin").setup({})
path_items = require("penguin.completion").collect("edit " .. path_root .. "/", {})

local saw_path_completion = false

for _, item in ipairs(path_items) do
  if item.text == "edit " .. path_child .. "/" and item.source == "completion" then
    saw_path_completion = true
    break
  end
end

assert(saw_path_completion)

completion._complete = function(query, kind)
  completion_calls[#completion_calls + 1] = {
    kind = kind,
    query = query,
  }

  return {}
end

completion_calls = {}
require("penguin").setup({
  completion = {
    debounce_ms = 10,
    command_strategies = {
      cd = "live",
      checkhealth = "prefix_cached_deferred",
    },
  },
})
require("penguin").open()
session = require("penguin")._session
assert(session)
completion_calls = {}
session:set_query("cd ../")
assert(#completion_calls == 1)
assert(completion_calls[1].kind == "cmdline")
assert(completion_calls[1].query == "cd ../")

completion._complete = original_complete
require("penguin").close()

local command_completion_calls = {}

completion._complete = function(query, kind)
  command_completion_calls[#command_completion_calls + 1] = {
    kind = kind,
    query = query,
  }

  if kind ~= "command" then
    return {}
  end

  if query == "Neogit" then
    return {
      "Neogit",
      "NeogitDiff",
      "NeogitDiffMain",
      "NeogitLog",
    }
  end

  if query == "Neogitdiff" then
    return {}
  end

  if query == "" then
    return {
      "Neogit",
      "NeogitDiff",
      "NeogitDiffMain",
      "NeogitLog",
    }
  end

  return {}
end

vim.fn.histadd(":", "NeogitDiffMain")

require("penguin").setup({})
require("penguin").open()
session = require("penguin")._session
assert(session)

session:set_query("Neogit")

local saw_neogit_diff_completion = false

for _, match in ipairs(session.matches) do
  if match.item.text == "NeogitDiff" and match.item.source == "completion" then
    saw_neogit_diff_completion = true
    break
  end
end

assert(saw_neogit_diff_completion)

command_completion_calls = {}
session:set_query("Neogitdiff")

local saw_neogit_diff_after_narrowing = false
local saw_neogit_diff_main_history = false

for _, match in ipairs(session.matches) do
  if match.item.text == "NeogitDiff" and match.item.source == "completion" then
    saw_neogit_diff_after_narrowing = true
  end

  if match.item.text == "NeogitDiffMain" and match.item.source == "history" then
    saw_neogit_diff_main_history = true
  end
end

assert(saw_neogit_diff_after_narrowing)
assert(saw_neogit_diff_main_history)
assert(#command_completion_calls == 2)
assert(command_completion_calls[1].kind == "command")
assert(command_completion_calls[1].query == "Neogitdiff")
assert(command_completion_calls[2].kind == "command")
assert(command_completion_calls[2].query == "")

completion._complete = original_complete
require("penguin").close()

require("penguin").setup({
  open_on_bare_enter = true,
})

local enter_mapped = false

for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
  if map.lhs == "<CR>" and map.desc == "Open penguin.nvim on bare Enter" then
    enter_mapped = true
    break
  end
end

assert(enter_mapped)
assert(require("penguin").handle_bare_enter() == "")
vim.wait(1000, function()
  return require("penguin")._session ~= nil
end)
assert(require("penguin")._session ~= nil)
require("penguin").close()

vim.cmd("help help")
assert(require("penguin").handle_bare_enter() == "<CR>")
assert(require("penguin")._session == nil)
vim.cmd("close")

vim.cmd("qa!")
