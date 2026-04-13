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
local exact

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
fuzzy_result = native.library.penguin_exact_matcher_find_fuzzy(exact.handle, "c-kh", #"c-kh", 10)
assert(fuzzy_result ~= nil)
assert(fuzzy_result.count == 1)
assert(fuzzy_result.results[0].index == 0)
assert(fuzzy_result.results[0].score == 611)

require("penguin").setup({
  native = {
    runtime_exact = true,
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
session:set_query("spl bot")
assert(#session.matches >= 1)
session:set_query("let g:penguin_selected = 7")
assert(session.matches[1].item.text == "let g:penguin_selected = 7")
session:delete_word_backward()
assert(session.query == "let g:penguin_selected =")
assert(vim.api.nvim_buf_get_lines(session.prompt_buf, 0, 1, false)[1] == "let g:penguin_selected =")
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

vim.cmd("qa!")
