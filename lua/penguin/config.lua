local M = {}

M.defaults = {
  direct_numeric_line_jumps_on_enter = true,
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
