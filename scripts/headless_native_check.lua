local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(source))
end

local root = repo_root()
local ffi = require("ffi")

vim.opt.runtimepath:append(root)
vim.cmd.source(vim.fs.joinpath(root, "plugin", "penguin.lua"))

local native = require("penguin.native")
local matcher = require("penguin.matcher")
local ui = require("penguin.ui")
local exact

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

assert(native.available)
assert(native.version() == 1)

exact = native.new_exact_matcher({
  { text = "CheckHealth" },
  { text = "Write" },
  { text = "healthcheck" },
})

assert(exact.handle ~= nil)
assert(exact.text_count == 3)
assert(exact.text_bytes == #("CheckHealthWritehealthcheck"))
assert(exact.result_capacity == 3)
assert(native.library.penguin_exact_matcher_text_length_at(exact.handle, 0) == #"CheckHealth")
assert(native.library.penguin_exact_matcher_text_length_at(exact.handle, 1) == #"Write")
assert(ffi.string(native.library.penguin_exact_matcher_lower_text_at(exact.handle, 0), #"CheckHealth") == "checkhealth")
assert(ffi.string(native.library.penguin_exact_matcher_lower_text_at(exact.handle, 1), #"Write") == "write")
assert(ffi.string(native.library.penguin_exact_matcher_lower_text_at(exact.handle, 2), #"healthcheck") == "healthcheck")
local query_result = native.library.penguin_exact_matcher_find_exact(exact.handle, "check", #"check")
local first_results = query_result.results
local fuzzy_result

assert(query_result ~= nil)
assert(query_result.count == 2)
assert(first_results ~= nil)
assert(query_result.results[0].index == 0)
assert(query_result.results[0].score == 320)
assert(query_result.results[1].index == 2)
assert(query_result.results[1].score == 266)

query_result = native.library.penguin_exact_matcher_find_exact(exact.handle, "check", #"check")
assert(query_result ~= nil)
assert(query_result.count == 2)
assert(query_result.results == first_results)

query_result = native.library.penguin_exact_matcher_find_exact(exact.handle, "zzz", #"zzz")
assert(query_result ~= nil)
assert(query_result.count == 0)
assert(query_result.results == first_results)
fuzzy_result = native.library.penguin_exact_matcher_find_fuzzy(exact.handle, "ckh", #"ckh", 10)
assert(fuzzy_result ~= nil)
assert(fuzzy_result.count == 1)
assert(fuzzy_result.results[0].index == 0)
assert(fuzzy_result.results[0].score == 276)
assert(fuzzy_result.results[0].match_span_count == 1)
assert(fuzzy_result.results[0].match_span_starts[0] == 3)
assert(fuzzy_result.results[0].match_span_ends[0] == 6)
fuzzy_result = native.library.penguin_exact_matcher_find_fuzzy(exact.handle, "c-kh", #"c-kh", 10)
assert(fuzzy_result ~= nil)
assert(fuzzy_result.count == 1)
assert(fuzzy_result.results[0].index == 0)
assert(fuzzy_result.results[0].score == 611)
assert(fuzzy_result.results[0].match_span_count == 0)

require("penguin").setup({
  native = {
    enabled = true,
  },
})

assert(matcher.backend_name() == "native-fuzzy-query")
assert(matcher.score("ckh", "checkhealth"))
assert(matcher.score("spl bot", "vertical botright split"))
assert(matcher.score("splbot", "vertical botright split"))
assert(not matcher.score("zz", "write"))

vim.fn.histadd(":", "checkhealth")
vim.fn.histadd(":", "vertical botright split")
vim.fn.histadd(":", "write")
vim.fn.histadd(":", "let g:penguin_selected = 7")

require("penguin").open()

local session = require("penguin")._session

assert(session)
assert(session.native_history_matcher ~= nil)
assert(session.native_history_matcher.handle ~= nil)
assert(session.native_history_matcher.text_count == #session.entries)
session:set_query("check")
assert(#session.matches >= 1)
session:set_query("ckh")
assert(#session.matches >= 1)
assert(#session.matches[1].match_ranges == 1)
assert(session.matches[1].match_ranges[1][1] == 3)
assert(session.matches[1].match_ranges[1][2] == 6)
local match_extmarks = extmarks_with_detail(session.results_buf, ui.namespace, "hl_group", "PenguinMatch")
local selection_extmarks = extmarks_with_detail(
  session.results_buf,
  ui.namespace,
  "line_hl_group",
  "Visual"
)
assert(#match_extmarks == 1)
assert(#selection_extmarks == 1)
assert(match_extmarks[1][2] == 0)
assert(match_extmarks[1][3] == 5)
assert(match_extmarks[1][4].end_col == 8)
assert(match_extmarks[1][4].priority > selection_extmarks[1][4].priority)

session.matches = {
  {
    item = {
      recency = 0,
      source = "history",
      source_rank = 1,
      text = "write",
    },
    match_ranges = {
      { 99, 104 },
    },
    score = 100,
  },
}
session.selection = 1
assert(pcall(ui.render, session))

local clamped_extmarks = extmarks_with_detail(session.results_buf, ui.namespace, "hl_group", "PenguinMatch")
assert(#clamped_extmarks == 0)

session:set_query("spl bot")
assert(#session.matches >= 1)
session:set_query("let g:penguin_selected = 7")
assert(session.matches[1].item.text == "let g:penguin_selected = 7")
session:delete_word_backward()
assert(session.query == "let g:penguin_selected =")
assert(vim.api.nvim_buf_get_lines(session.prompt_buf, 0, 1, false)[1] == ": let g:penguin_selected =")
assert(#session.matches >= 1)

vim.api.nvim_buf_set_lines(session.prompt_buf, 0, -1, false, { ": write" })
vim.api.nvim_exec_autocmds("TextChangedI", {
  buffer = session.prompt_buf,
})
assert(session.query == "write")
assert(session.matches[1].item.text == "write")

vim.api.nvim_buf_set_lines(session.prompt_buf, 0, -1, false, { ": " })
vim.api.nvim_exec_autocmds("TextChangedI", {
  buffer = session.prompt_buf,
})
assert(session.query == "")
assert(#session.matches >= 1)

local saw_native_history_match = false
local saw_completion_match = false

session:set_query("spl bot")

for _, match in ipairs(session.matches) do
  if match.item.text == "vertical botright split" and match.item.source == "history" then
    saw_native_history_match = true
    break
  end
end

assert(saw_native_history_match)

session:set_query("check")

for _, match in ipairs(session.matches) do
  if match.item.source == "completion" then
    saw_completion_match = true
    break
  end
end

assert(saw_completion_match)

require("penguin").close()

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

local completion = require("penguin.completion")
local original_complete = completion._complete
local completion_calls = {}

completion._complete = function(query, kind)
  completion_calls[#completion_calls + 1] = {
    kind = kind,
    query = query,
  }

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
  native = {
    enabled = true,
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

completion._complete = original_complete
require("penguin").close()

local path_root = vim.fn.tempname()
local path_child = vim.fs.joinpath(path_root, "penguinpathchild")
local path_items

assert(vim.fn.mkdir(path_child, "p") == 1)

require("penguin").setup({
  native = {
    enabled = true,
  },
})
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
  native = {
    enabled = true,
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

require("penguin").setup({
  open_on_bare_enter = true,
  native = {
    enabled = true,
  },
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
