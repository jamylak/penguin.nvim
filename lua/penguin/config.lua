local M = {}

M.defaults = {
  completion = {
    -- Command-name completion stays synchronous. Argument completion strategy is
    -- selected per command so cheap path-oriented commands can stay fully live
    -- while known slow commands such as `:checkhealth` can be deferred.
    debounce_ms = 75,
    command_strategies = {
      checkhealth = "prefix_cached_deferred",
    },
  },
  open_on_bare_enter = false,
  native = {
    enabled = true,
    auto_build = true,
    benchmark_only_lua = false,
  },
  ui = {
    border = "rounded",
    max_results = 12,
    match_highlights = true,
    width = 72,
  },
}

function M.merge(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
